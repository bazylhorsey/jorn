port module Main exposing (main)

{-| A counter that never touches the DOM itself.

It sends the initial tree and then patches out of `toClient`, and takes
browser events in through `fromClient`. The same compiled program runs in two
places: in `index.html`, where client/jorn.js applies the patches to the page,
and in `run.mjs`, headless in Node, the way a server component would. Put a
websocket between the two and you have a server component; that runtime is
what Jorn builds next.

-}

import Jorn.Attribute as Attr
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Events
import Jorn.Internal.Event as Routing
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)


port toClient : Value -> Cmd msg


port fromClient : (Value -> msg) -> Sub msg



-- YOUR COMPONENT: ordinary Elm Architecture


type alias Model =
    { count : Int
    , name : String
    }


type Msg
    = Increment
    | Decrement
    | Rename String


init : Model
init =
    { count = 0, name = "world" }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }

        Rename name ->
            { model | name = name }


view : Model -> Element Msg
view model =
    Html.main_ []
        [ Html.h1 [] [ Element.text ("Hello, " ++ model.name) ]
        , Html.input [ Attr.value model.name, Events.onInput Rename ]
        , Html.button [ Events.onClick Decrement ] [ Element.text "-" ]
        , Html.span [] [ Element.text (String.fromInt model.count) ]
        , Html.button [ Events.onClick Increment ] [ Element.text "+" ]
        ]



-- THE GLUE: what a Jorn runtime does for you


main : Program () Model Value
main =
    Platform.worker
        { init = \_ -> ( init, send "mount" (Jorn.Patch.encodeHtml (view init)) )
        , update = receive
        , subscriptions = \_ -> fromClient identity
        }


receive : Value -> Model -> ( Model, Cmd msg )
receive raw model =
    let
        routed =
            Decode.decodeValue Routing.decoder raw
                |> Result.mapError Decode.errorToString
                |> Result.andThen
                    (\incoming ->
                        Routing.route incoming (view model)
                            |> Result.mapError Routing.errorToString
                    )
    in
    case routed of
        Ok msg ->
            let
                next =
                    update msg model
            in
            ( next, send "patches" (Jorn.Patch.encode (Jorn.Patch.diff (view model) (view next))) )

        Err problem ->
            ( model, send "error" (Encode.string problem) )


send : String -> Value -> Cmd msg
send kind payload =
    toClient (Encode.object [ ( kind, payload ) ])
