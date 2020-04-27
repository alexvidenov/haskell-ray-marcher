{-|
A ray macher implemented in haskell.
-}

module Marcher
  ( Vec3(..)
  , dot
  , scale
  , mag
  , normalize
  , Color
  , colorize
  , red
  , green
  , blue
  , black
  , white
  , gray
  , darkRed
  , darkYellow
  , pink
  , mixColors
  , Ray
  , rayRender
  , rayMarch
  , getRays
  , Radius
  , Position
  , Scene
  , Material (..)
  , sphere
  , spacedPoints
  , mergeScenes
  , ImageSettings (..)
  , writePPM
  , clamp
  , colorToRGB
  , defaultSettings
  , defaultScene
  , equalWithinError
  ) where

import Codec.Image.PPM ( ColorArray, ppm_p6 )
import System.IO ( withBinaryFile, hPutStr, IOMode(WriteMode) )

-- | A collection of 3 doubles.
newtype Vec3 = Vec3 (Double, Double, Double) deriving (Show,Eq)

instance Num Vec3 where
    (Vec3 (x, y, z)) + (Vec3 (x1, y1, z1)) = Vec3 ((x + x1), (y + y1), (z + z1))
    negate (Vec3 (x, y, z)) = Vec3 ((-x), (-y), (-z))
    x - y = x + negate y
    abs (Vec3 (x, y, z)) = Vec3 ((abs x), (abs y), (abs z))
    (Vec3 (x, y, z)) * (Vec3 (x1, y1, z1)) = Vec3 ((x * x1), (y * y1), (z * z1))
    fromInteger x = let y = fromInteger x in Vec3 (y, y, y)
    signum (Vec3 (x, y, z)) = Vec3 ((signum x), (signum y), (signum z))


-- | The dot product of two vectors
(Vec3 (x, y, z)) `dot` (Vec3 (a, s, d)) = x*a + y*s + z*d
-- | Scale a vector's magnitude by a number.
a `scale` (Vec3 (x, y, z)) = Vec3 ((a*x), (a*y), (a*z))

-- | (See 'mag').
squared_mag :: Vec3 -> Double
squared_mag v3@(Vec3 (x, y, z)) = (x * x + y * y + z * z)

-- | Returns the magnitude (i.e. the length) of a vector.
mag :: Vec3 -> Double
mag v = sqrt (squared_mag v)

-- | Scale a vector so that it will have a magnitude of 1
normalize :: Vec3 -> Vec3
normalize (Vec3 (0, 0, 0)) = error "Cannot normalize a vector with magnitude 0"
normalize v = ( 1 / mag v) `scale` v

equalWithinError :: (Num a, Ord a) => a -> a -> a -> Bool
equalWithinError epsilon a b = abs (a-b) < epsilon

------------------------------------------------------------

-- | Color is stored in RGB format.
type Color = Vec3

-- | Sets the color of an entire scene to some color.
colorize :: Color -> Scene -> Scene
colorize c s pt =
  let (d, Material _ p g) = s pt -- Evaluating the scene
  in (d, Material c p g) -- Adding the color to the scene.

red, green, blue, black, white :: Color
-- | RGB FF0000
red = Vec3 (1,0,0)
-- | RGB 00FF00
green = Vec3 (0,1,0)
-- | RGB 0000FF
blue = Vec3 (0,0,1)
-- | RGB 000000
black = Vec3 (0,0,0)
-- | RGB FFFFFF
white = Vec3 (1,1,1)
-- | RGB 7F7F7F
gray = Vec3 (0.5,0.5,0.5)

darkRed, darkYellow, pink :: Color
-- | RGB #800000
darkRed = Vec3 (0.5,0,0)
-- | RGB #808000
darkYellow = Vec3 (0.5,0.5,0)
-- | RGB #FF8080
pink = Vec3 (1,0.5,0.5)


-- | Mix two colors additively. Useful for making new colors and not for rendering since it doesn't follow the physical light model.
-- Red + Black   = Dark Red
-- Red + Green   = Dark Yellow
-- Red + White   = Pink
-- Black + White = Gray
mixColors :: Color -> Color -> Color
mixColors a b = (a + b) * gray

------------------------------------------------------------

-- | A pair of a position and a direction in 3D space
type Ray = (Position
           ,Direction)

-- | A direction in 3D space stored as a normalized vector
type Direction = Vec3

-- | Marches a ray through a scene and then does shading, reflections and refractions.
rayRender :: ImageSettings -> Scene -> Ray -> Color
rayRender sett s ray = clamp $ case rayMarch sett s ray of
    Nothing -> getBackgroundColor sett
    Just pos -> let color = getColor $ snd $ s pos
              in case rayMarch sett newscene (pos + 3*epsilon `scale` calcNormal sett s pos, normalize $ light - pos) of
        Nothing -> color
        Just newpos -> if equalWithinError epsilon 0 $ mag (light-newpos) then color else gray * color

  where light = getSunPosition sett
        newscene = mergeScenes s $ pointToScene light
        epsilon = getTolerance sett

-- | Marches a ray through a scene until it hits an object. Returns Nothing if it goes outside the scene.
rayMarch :: ImageSettings -> Scene -> Ray -> Maybe Position
rayMarch sett s (pos,dir)
    | end <= 0 = Nothing
    | equalWithinError epsilon 0 dist = Just pos
    | otherwise = rayMarch sett{getRenderDistance=end-dist} s (pos + dist `scale` dir, dir) -- Each time lowering the distance to the end with the distance we traveled.
    where   (dist, Material color _ _) = s pos
            end = getRenderDistance sett
            epsilon = getTolerance sett


-- | Calculates the surface normals of a given scene.
calcNormal :: ImageSettings -> Scene -> Position -> Direction
calcNormal sett s pt = normalize (Vec3 (x, y, z)) -- pt is the current position of our view ray.
    where   epsilon = getTolerance sett
            x = fst ( s (pt + Vec3 (epsilon, 0, 0) )) - fst (s (pt - Vec3 (epsilon, 0, 0)) )
            y = fst ( s (pt + Vec3 (0, epsilon, 0) )) - fst (s (pt - Vec3 (0, epsilon, 0)) )
            z = fst ( s (pt + Vec3 (0, 0, epsilon) )) - fst (s (pt - Vec3 (0, 0, epsilon)) )

-- | Produces an array of rays to later be marched.
getRays :: ImageSettings -> [[Ray]]
getRays setting = [[ (Vec3 (0, 0, 0), normalize (Vec3 (x, (-y), z)) ) -- First Ray has coordinates [-1,-(-1)].
                   | x <- widthCoords setting ]
                   | y <- heightCoords setting ]
    where z = (tan (pi - getFieldOfView setting / 2))
          widthCoords setting = spacedPoints $ getImageWidth setting
          heightCoords setting = spacedPoints $ getImageHeight setting



-- | Generates N doubles from -1 to 1, equally spaced.
spacedPoints :: Int -> [Double]
spacedPoints n = f <$> fromIntegral <$> [0..n-1]
  where f x = (-1) + x*d
        d = 2/(fromIntegral n - 1)

------------------------------------------------------------

-- | Commonly indicates a distance from a given point.
type Radius = Double
-- | A position in 3D space
type Position = Vec3
-- | One or several objects in space.
type Scene = Position -> (Radius, Material)
-- | All properties describing an object other than its shape.
data Material = Material
  { getColor :: Color
  , getSpecularLighting :: Double -- ^ Specular lighting is the bright spot on shiny objects.
  , getGloss :: Double -- ^ Gloss defines how "soft"/"hard" the reflection is.
  } deriving (Show, Eq)

-- | Defines a sphere at a given position and with a given radius.
sphere :: Position -> Radius -> Scene
sphere pos r = \pt -> (mag (pos-pt) - r, defaultMaterial)

-- | Combines two scenes into a single scene.
mergeScenes :: Scene -> Scene -> Scene
mergeScenes scene1 scene2 pt
    | d1 < d2 = res1 -- Picks the minimum distance and the corresponding Material
    | otherwise = res2
    where   res1@(d1, _) = scene1 pt
            res2@(d2, _) = scene2 pt

pointToScene :: Position -> Scene
pointToScene p j = (mag (p-j), defaultMaterial)

------------------------------------------------------------

-- | A data type holding all of the rendering settings. This is everything needed to create a rendering, excluding the scene itself.
data ImageSettings = ImageSettings
 { getImageWidth :: Int -- ^ In pixels.
 , getImageHeight :: Int -- ^ In pixels.
 , getFieldOfView :: Double -- ^ In radians.
 , getRenderDistance :: Double -- ^ How far to march before giving up.
 , getTolerance :: Double -- ^ How close to an object to get before counting the ray as hitting that object.
 , getBackgroundColor :: Color -- ^ The background color of a scene.
 , getSunPosition :: Position -- ^ TEMPORARY. The position of the light source.
 }

-- | Clamps a color so that every component is between 0 and 1
clamp :: Color -> Color
clamp (Vec3 (r, g, b)) = Vec3 (clampFloat r, clampFloat g, clampFloat b)
    where clampFloat f = max 0 (min 1 f)

-- | Prepares a color for outputting
colorToRGB :: (Integral a, Integral b, Integral c)
           => Color
           -> (a, b, c) -- ^ Returns RGB clamped triple
colorToRGB (Vec3 (r,g,b)) = (scaleFloat r, scaleFloat g, scaleFloat b)
    where scaleFloat f = round ( 255 * f )

-- | Writes a ColorArray to a file.
writePPM :: FilePath
         -> [ColorArray] -- ^ ColorArray is the Codec.Image.PPM.Color representation of a color (triple of Integers)
         -> IO ()
writePPM fileName img = do
    let imgData = ppm_p6 img -- Returns String version of the ColorArray.
    withBinaryFile fileName WriteMode (\h -> hPutStr h imgData) -- Opens a file in Binary mode and writes the imgData String in it.

------------------------------------------------------------

-- | Default image settings.
defaultSettings = ImageSettings 1024 1024 (pi/2) 100 0.00001 black (Vec3 (10,10,(10-3)))

-- | An example scene.
defaultScene :: Scene
defaultScene = mergeScenes
                  (colorize red $ sphere (Vec3 (0, 0, (-3))) 1)
                  (colorize blue $ sphere (Vec3 (1, 1, (-2))) 0.1)

-- | Default material when a material is unspecified.
defaultMaterial = Material white 20 0.5
