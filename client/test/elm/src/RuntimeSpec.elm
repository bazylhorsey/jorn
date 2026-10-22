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
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Task


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


{-| The app's own ports, for JavaScript around it: `add` adds to the count,
and `total` reports the count after each `add`.
-}
port add : (Int -> msg) -> Sub msg


port total : Int -> Cmd msg


type alias Model =
    { count : Int
    , open : Bool
    , name : String
    , log : List String
    , keys : List String
    }


type Msg
    = Increment
    | Open
    | Typed String
    | Before
    | Painted
    | FromTask
    | Pressed String
    | Bubbled String
    | Add Int


main : Jorn.Program Int Model Msg
main =
    Jorn.application
        { init = \count -> ( { count = count, open = False, name = "", log = [], keys = [] }, Effect.none )
        , update = update
        , view = view
        , subscriptions = \_ -> add Add
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

        Pressed key ->
            ( { model | keys = model.keys ++ [ key ] }, Effect.none )

        Bubbled key ->
            ( { model | keys = model.keys ++ [ "bubbled " ++ key ] }, Effect.none )

        Add n ->
            ( { model | count = model.count + n }, Effect.fromCmd (total (model.count + n)) )


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
        , Html.div [ Event.onKeydown Bubbled ]
            [ Html.input
                [ Attr.id "keys"
                , Event.advanced "keydown"
                    (Decode.map
                        (\key ->
                            { message = Pressed key
                            , preventDefault = key == "Enter"
                            , stopPropagation = key == "Escape"
                            }
                        )
                        Event.key
                    )
                ]
            ]
        , Html.span [ Attr.id "pressed" ] [ Element.text (String.join "," model.keys) ]
        ]
