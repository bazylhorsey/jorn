module Jorn.Event exposing
    ( on, custom, Options
    , onClick, onInput, onCheck, onSubmit
    , preventDefault, stopPropagation, include
    , targetValue, targetChecked
    )

{-| Event handlers.

Options are static: the client must decide whether to call `preventDefault`
the moment the event fires, without waiting on a server. `include` lists the
event fields a server component needs serialized and sent back, as dotted
paths like `"target.value"`. In client mode the whole event is available and
`include` is ignored.

An option is an attribute of the handler it applies to:

    form [ Event.onSubmit Submit ] [...]

    form [ Event.preventDefault (Event.onSubmit Submit) ] [...]

Options on one handler merge, so an option set twice asks for both things. An
option only reaches the handler it wraps.


# Handlers

@docs on, custom, Options


# Common events

@docs onClick, onInput, onCheck, onSubmit


# Options

@docs preventDefault, stopPropagation, include


# Decoders

@docs targetValue, targetChecked

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Internal.Vdom as Vdom
import Json.Decode as Decode exposing (Decoder)


{-| How the client should treat an event before handing it to Elm.
-}
type alias Options msg =
    Attribute msg -> Attribute msg


{-| Handle an event with no options beyond the ones on the element.
-}
on : String -> Decoder msg -> Attribute msg
on name decoder =
    Vdom.On name decoder


{-| Handle an event with explicit options.
-}
custom : String -> Options msg -> Decoder msg -> Attribute msg
custom name options decoder =
    options (Vdom.On name decoder)


{-| -}
onClick : msg -> Attribute msg
onClick msg =
    on "click" (Decode.succeed msg)


{-| Includes `target.value`.
-}
onInput : (String -> msg) -> Attribute msg
onInput tagger =
    custom "input" (include [ "target.value" ]) (Decode.map tagger targetValue)


{-| Fires on `change`. Includes `target.checked`.
-}
onCheck : (Bool -> msg) -> Attribute msg
onCheck tagger =
    custom "change" (include [ "target.checked" ]) (Decode.map tagger targetChecked)


{-| Prevents the browser's default form submission.
-}
onSubmit : msg -> Attribute msg
onSubmit msg =
    custom "submit" preventDefault (Decode.succeed msg)


{-| Call `preventDefault` on the event before it reaches Elm.
-}
preventDefault : Options msg
preventDefault handler =
    Vdom.Options { preventDefault = True, stopPropagation = False, include = [] } handler


{-| Stop the event from bubbling past the element.
-}
stopPropagation : Options msg
stopPropagation handler =
    Vdom.Options { preventDefault = False, stopPropagation = True, include = [] } handler


{-| Send these event fields back to Elm, as dotted paths like `"target.value"`.

The field is copied off the event into plain JSON, keeping its nesting.

-}
include : List String -> Options msg
include paths handler =
    Vdom.Options { preventDefault = False, stopPropagation = False, include = paths } handler


{-| -}
targetValue : Decoder String
targetValue =
    Decode.at [ "target", "value" ] Decode.string


{-| -}
targetChecked : Decoder Bool
targetChecked =
    Decode.at [ "target", "checked" ] Decode.bool
