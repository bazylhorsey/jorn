module Jorn.Element.Svg exposing
    ( namespace
    , svg, g, defs, symbol, use_, a, switch, marker, mask, pattern, view
    , missingGlyph
    , circle, ellipse, line, path, polygon, polyline, rect
    , text, tspan, textPath
    , image, foreignObject
    , linearGradient, radialGradient, stop
    , clipPath
    , desc, metadata, title
    , animate, animateMotion, animateTransform, mpath, set
    , filter, feBlend, feColorMatrix, feComponentTransfer, feComposite
    , feConvolveMatrix, feDiffuseLighting, feDisplacementMap, feDropShadow
    , feFlood, feFuncA, feFuncB, feFuncG, feFuncR, feGaussianBlur, feImage
    , feMerge, feMergeNode, feMorphology, feOffset, feSpecularLighting, feTile
    , feTurbulence
    , feDistantLight, fePointLight, feSpotLight
    , script, style
    )

{-| One function per SVG element, each in the SVG namespace. Attributes go
through `Jorn.Attribute.attribute`:

    Svg.svg [ Attribute.attribute "viewBox" "0 0 100 100" ]
        [ Svg.circle
            [ Attribute.attribute "cx" "50"
            , Attribute.attribute "cy" "50"
            , Attribute.attribute "r" "40"
            ]
            []
        ]

Anything missing here works through `Jorn.Element.namespaced` with
`namespace`.


# Namespace

@docs namespace


# Containers

@docs svg, g, defs, symbol, use_, a, switch, marker, mask, pattern, view
@docs missingGlyph


# Shapes

@docs circle, ellipse, line, path, polygon, polyline, rect


# Text

`text` here is the SVG `<text>` element. Text nodes still come from `Jorn.Element.text`:

    Svg.text [ Attribute.attribute "x" "10" ] [ Element.text "Hello" ]

@docs text, tspan, textPath


# Graphics

@docs image, foreignObject


# Gradients

@docs linearGradient, radialGradient, stop


# Clipping

@docs clipPath


# Descriptive

@docs desc, metadata, title


# Animation

@docs animate, animateMotion, animateTransform, mpath, set


# Filters

@docs filter, feBlend, feColorMatrix, feComponentTransfer, feComposite
@docs feConvolveMatrix, feDiffuseLighting, feDisplacementMap, feDropShadow
@docs feFlood, feFuncA, feFuncB, feFuncG, feFuncR, feGaussianBlur, feImage
@docs feMerge, feMergeNode, feMorphology, feOffset, feSpecularLighting, feTile
@docs feTurbulence


# Lights

@docs feDistantLight, fePointLight, feSpotLight


# Other

@docs script, style

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Element exposing (Element, namespaced)


{-| The SVG namespace, `http://www.w3.org/2000/svg`.
-}
namespace : String
namespace =
    "http://www.w3.org/2000/svg"


{-| -}
svg : List (Attribute msg) -> List (Element msg) -> Element msg
svg =
    namespaced namespace "svg"


{-| -}
g : List (Attribute msg) -> List (Element msg) -> Element msg
g =
    namespaced namespace "g"


{-| -}
defs : List (Attribute msg) -> List (Element msg) -> Element msg
defs =
    namespaced namespace "defs"


{-| -}
symbol : List (Attribute msg) -> List (Element msg) -> Element msg
symbol =
    namespaced namespace "symbol"


{-| -}
use_ : List (Attribute msg) -> List (Element msg) -> Element msg
use_ =
    namespaced namespace "use"


{-| -}
a : List (Attribute msg) -> List (Element msg) -> Element msg
a =
    namespaced namespace "a"


{-| -}
switch : List (Attribute msg) -> List (Element msg) -> Element msg
switch =
    namespaced namespace "switch"


{-| -}
marker : List (Attribute msg) -> List (Element msg) -> Element msg
marker =
    namespaced namespace "marker"


{-| -}
mask : List (Attribute msg) -> List (Element msg) -> Element msg
mask =
    namespaced namespace "mask"


{-| -}
pattern : List (Attribute msg) -> List (Element msg) -> Element msg
pattern =
    namespaced namespace "pattern"


{-| -}
view : List (Attribute msg) -> List (Element msg) -> Element msg
view =
    namespaced namespace "view"


{-| `<missing-glyph>`.
-}
missingGlyph : List (Attribute msg) -> List (Element msg) -> Element msg
missingGlyph =
    namespaced namespace "missing-glyph"


{-| -}
circle : List (Attribute msg) -> List (Element msg) -> Element msg
circle =
    namespaced namespace "circle"


{-| -}
ellipse : List (Attribute msg) -> List (Element msg) -> Element msg
ellipse =
    namespaced namespace "ellipse"


{-| -}
line : List (Attribute msg) -> List (Element msg) -> Element msg
line =
    namespaced namespace "line"


{-| -}
path : List (Attribute msg) -> List (Element msg) -> Element msg
path =
    namespaced namespace "path"


{-| -}
polygon : List (Attribute msg) -> List (Element msg) -> Element msg
polygon =
    namespaced namespace "polygon"


{-| -}
polyline : List (Attribute msg) -> List (Element msg) -> Element msg
polyline =
    namespaced namespace "polyline"


{-| -}
rect : List (Attribute msg) -> List (Element msg) -> Element msg
rect =
    namespaced namespace "rect"


{-| -}
text : List (Attribute msg) -> List (Element msg) -> Element msg
text =
    namespaced namespace "text"


{-| -}
tspan : List (Attribute msg) -> List (Element msg) -> Element msg
tspan =
    namespaced namespace "tspan"


{-| -}
textPath : List (Attribute msg) -> List (Element msg) -> Element msg
textPath =
    namespaced namespace "textPath"


{-| -}
image : List (Attribute msg) -> List (Element msg) -> Element msg
image =
    namespaced namespace "image"


{-| -}
foreignObject : List (Attribute msg) -> List (Element msg) -> Element msg
foreignObject =
    namespaced namespace "foreignObject"


{-| -}
linearGradient : List (Attribute msg) -> List (Element msg) -> Element msg
linearGradient =
    namespaced namespace "linearGradient"


{-| -}
radialGradient : List (Attribute msg) -> List (Element msg) -> Element msg
radialGradient =
    namespaced namespace "radialGradient"


{-| -}
stop : List (Attribute msg) -> List (Element msg) -> Element msg
stop =
    namespaced namespace "stop"


{-| -}
clipPath : List (Attribute msg) -> List (Element msg) -> Element msg
clipPath =
    namespaced namespace "clipPath"


{-| -}
desc : List (Attribute msg) -> List (Element msg) -> Element msg
desc =
    namespaced namespace "desc"


{-| -}
metadata : List (Attribute msg) -> List (Element msg) -> Element msg
metadata =
    namespaced namespace "metadata"


{-| -}
title : List (Attribute msg) -> List (Element msg) -> Element msg
title =
    namespaced namespace "title"


{-| -}
animate : List (Attribute msg) -> List (Element msg) -> Element msg
animate =
    namespaced namespace "animate"


{-| -}
animateMotion : List (Attribute msg) -> List (Element msg) -> Element msg
animateMotion =
    namespaced namespace "animateMotion"


{-| -}
animateTransform : List (Attribute msg) -> List (Element msg) -> Element msg
animateTransform =
    namespaced namespace "animateTransform"


{-| -}
mpath : List (Attribute msg) -> List (Element msg) -> Element msg
mpath =
    namespaced namespace "mpath"


{-| -}
set : List (Attribute msg) -> List (Element msg) -> Element msg
set =
    namespaced namespace "set"


{-| -}
filter : List (Attribute msg) -> List (Element msg) -> Element msg
filter =
    namespaced namespace "filter"


{-| -}
feBlend : List (Attribute msg) -> List (Element msg) -> Element msg
feBlend =
    namespaced namespace "feBlend"


{-| -}
feColorMatrix : List (Attribute msg) -> List (Element msg) -> Element msg
feColorMatrix =
    namespaced namespace "feColorMatrix"


{-| -}
feComponentTransfer : List (Attribute msg) -> List (Element msg) -> Element msg
feComponentTransfer =
    namespaced namespace "feComponentTransfer"


{-| -}
feComposite : List (Attribute msg) -> List (Element msg) -> Element msg
feComposite =
    namespaced namespace "feComposite"


{-| -}
feConvolveMatrix : List (Attribute msg) -> List (Element msg) -> Element msg
feConvolveMatrix =
    namespaced namespace "feConvolveMatrix"


{-| -}
feDiffuseLighting : List (Attribute msg) -> List (Element msg) -> Element msg
feDiffuseLighting =
    namespaced namespace "feDiffuseLighting"


{-| -}
feDisplacementMap : List (Attribute msg) -> List (Element msg) -> Element msg
feDisplacementMap =
    namespaced namespace "feDisplacementMap"


{-| -}
feDropShadow : List (Attribute msg) -> List (Element msg) -> Element msg
feDropShadow =
    namespaced namespace "feDropShadow"


{-| -}
feFlood : List (Attribute msg) -> List (Element msg) -> Element msg
feFlood =
    namespaced namespace "feFlood"


{-| -}
feFuncA : List (Attribute msg) -> List (Element msg) -> Element msg
feFuncA =
    namespaced namespace "feFuncA"


{-| -}
feFuncB : List (Attribute msg) -> List (Element msg) -> Element msg
feFuncB =
    namespaced namespace "feFuncB"


{-| -}
feFuncG : List (Attribute msg) -> List (Element msg) -> Element msg
feFuncG =
    namespaced namespace "feFuncG"


{-| -}
feFuncR : List (Attribute msg) -> List (Element msg) -> Element msg
feFuncR =
    namespaced namespace "feFuncR"


{-| -}
feGaussianBlur : List (Attribute msg) -> List (Element msg) -> Element msg
feGaussianBlur =
    namespaced namespace "feGaussianBlur"


{-| -}
feImage : List (Attribute msg) -> List (Element msg) -> Element msg
feImage =
    namespaced namespace "feImage"


{-| -}
feMerge : List (Attribute msg) -> List (Element msg) -> Element msg
feMerge =
    namespaced namespace "feMerge"


{-| -}
feMergeNode : List (Attribute msg) -> List (Element msg) -> Element msg
feMergeNode =
    namespaced namespace "feMergeNode"


{-| -}
feMorphology : List (Attribute msg) -> List (Element msg) -> Element msg
feMorphology =
    namespaced namespace "feMorphology"


{-| -}
feOffset : List (Attribute msg) -> List (Element msg) -> Element msg
feOffset =
    namespaced namespace "feOffset"


{-| -}
feSpecularLighting : List (Attribute msg) -> List (Element msg) -> Element msg
feSpecularLighting =
    namespaced namespace "feSpecularLighting"


{-| -}
feTile : List (Attribute msg) -> List (Element msg) -> Element msg
feTile =
    namespaced namespace "feTile"


{-| -}
feTurbulence : List (Attribute msg) -> List (Element msg) -> Element msg
feTurbulence =
    namespaced namespace "feTurbulence"


{-| -}
feDistantLight : List (Attribute msg) -> List (Element msg) -> Element msg
feDistantLight =
    namespaced namespace "feDistantLight"


{-| -}
fePointLight : List (Attribute msg) -> List (Element msg) -> Element msg
fePointLight =
    namespaced namespace "fePointLight"


{-| -}
feSpotLight : List (Attribute msg) -> List (Element msg) -> Element msg
feSpotLight =
    namespaced namespace "feSpotLight"


{-| -}
script : List (Attribute msg) -> List (Element msg) -> Element msg
script =
    namespaced namespace "script"


{-| -}
style : List (Attribute msg) -> List (Element msg) -> Element msg
style =
    namespaced namespace "style"
