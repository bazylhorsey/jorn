port module RuntimeSpec exposing (main)

{-| A small app for client/test/runtime.mjs, using every kind of effect, so
the test can drive `start` and the runtime end to end in jsdom.
-}

import Jorn
import Jorn.Attribute as Attr
import Jorn.Effect as Effect exposing (Effect)
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Json.Encode as Encode exposing (Value)
import Task


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


type alias Model =
    { count : Int
    , open : Bool
    , name : String
    , log : List String
    }


type Msg
    = Increment
    | Open
    | Typed String
    | Before
    | Painted
    | FromTask


main : Jorn.Program Int Model Msg
main =
    Jorn.application
        { init = \count -> ( { count = count, open = False, name = "", log = [] }, Effect.none )
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , ports = { toJorn = toJorn, fromJorn = fromJorn }
        }


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )

        Open ->
            ( { model | open = True }
            , Effect.batch
                [ Effect.focus "field"
                , Effect.beforePaint Before
                , Effect.afterPaint Painted
                , Effect.event "opened" (Encode.int model.count)
                , Effect.client "record" (Encode.string "opened")
                , Effect.fromCmd (Task.perform (\_ -> FromTask) (Task.succeed ()))
                ]
            )

        Typed name ->
            ( { model | name = name }, Effect.none )

        Before ->
            ( { model | log = model.log ++ [ "before" ] }, Effect.none )

        Painted ->
            ( { model | log = model.log ++ [ "painted" ] }, Effect.none )

        FromTask ->
            ( { model | log = model.log ++ [ "task" ] }, Effect.none )


view : Model -> Element Msg
view model =
    Html.div []
        [ Html.button [ Attr.id "increment", Event.onClick Increment ] [ Element.text (String.fromInt model.count) ]
        , Html.button [ Attr.id "open", Event.onClick Open ] []
        , if model.open then
            Html.input [ Attr.id "field", Event.onInput Typed ]

          else
            Element.none
        , Html.span [ Attr.id "name" ] [ Element.text model.name ]
        , Html.span [ Attr.id "log" ] [ Element.text (String.join "," model.log) ]
        ]
