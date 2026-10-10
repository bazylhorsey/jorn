module Jorn.Html.Events exposing
    ( on, custom, Options
    , onClick, onInput, onCheck, onSubmit
    , targetValue, targetChecked
    )

{-| Event handlers.

Options are static: the client must decide whether to call `preventDefault`
the moment the event fires, without waiting on a server. `include` lists the
event fields a server component needs serialized and sent back, as dotted
paths like `"target.value"`. In client mode the whole event is available and
`include` is ignored.


# Handlers

@docs on, custom, Options


# Common events

@docs onClick, onInput, onCheck, onSubmit


# Decoders

@docs targetValue, targetChecked

-}

import Jorn.Html exposing (Attribute)
import Jorn.Internal.Vdom as Vdom
import Json.Decode as Decode exposing (Decoder)


{-| How the client should treat an event before handing it to Elm.
-}
type alias Options =
    { preventDefault : Bool
    , stopPropagation : Bool
    , include : List String
    }


{-| Handle an event with default options and nothing extra included.
-}
on : String -> Decoder msg -> Attribute msg
on name decoder =
    Vdom.On name Vdom.defaultOptions decoder


{-| Handle an event with explicit options.
-}
custom : String -> Options -> Decoder msg -> Attribute msg
custom =
    Vdom.On


{-| -}
onClick : msg -> Attribute msg
onClick msg =
    on "click" (Decode.succeed msg)


{-| Includes `target.value`.
-}
onInput : (String -> msg) -> Attribute msg
onInput tagger =
    custom "input"
        { preventDefault = False, stopPropagation = False, include = [ "target.value" ] }
        (Decode.map tagger targetValue)


{-| Fires on `change`. Includes `target.checked`.
-}
onCheck : (Bool -> msg) -> Attribute msg
onCheck tagger =
    custom "change"
        { preventDefault = False, stopPropagation = False, include = [ "target.checked" ] }
        (Decode.map tagger targetChecked)


{-| Prevents the browser's default form submission.
-}
onSubmit : msg -> Attribute msg
onSubmit msg =
    custom "submit"
        { preventDefault = True, stopPropagation = False, include = [] }
        (Decode.succeed msg)


{-| -}
targetValue : Decoder String
targetValue =
    Decode.at [ "target", "value" ] Decode.string


{-| -}
targetChecked : Decoder Bool
targetChecked =
    Decode.at [ "target", "checked" ] Decode.bool
