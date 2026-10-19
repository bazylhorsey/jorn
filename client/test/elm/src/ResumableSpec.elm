port module ResumableSpec exposing (main)

{-| A small `Jorn.resumable` app for server/test/deploy.mjs. Its log records
how it started, so a test can tell a session that picked up a saved model
from one that ran `init`.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Task


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


type alias Model =
    { count : Int
    , name : String
    , log : List String
    }


type Msg
    = Increment
    | Typed String
    | Started


main : Jorn.Program Int Model Msg
main =
    Jorn.resumable
        { init = \count -> ( { count = count, name = "", log = [] }, Effect.fromCmd (Task.perform (\_ -> Started) (Task.succeed ())) )
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        , encode = encode
        , decoder = decoder
        }


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )

        Typed name ->
            ( { model | name = name }, Effect.none )

        Started ->
            ( { model | log = model.log ++ [ "started" ] }, Effect.none )


view : Model -> Element Msg
view model =
    Html.div []
        [ Html.button [ Attr.id "increment", Event.onClick Increment ] [ Element.text (String.fromInt model.count) ]
        , Html.input [ Attr.id "field", Event.onInput Typed ]
        , Html.span [ Attr.id "name" ] [ Element.text model.name ]
        , Html.span [ Attr.id "log" ] [ Element.text (String.join "," model.log) ]
        ]


encode : Model -> Value
encode model =
    Encode.object
        [ ( "count", Encode.int model.count )
        , ( "name", Encode.string model.name )
        , ( "log", Encode.list Encode.string model.log )
        ]


decoder : Decode.Decoder Model
decoder =
    Decode.map3 Model
        (Decode.field "count" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "log" (Decode.list Decode.string))
