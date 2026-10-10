module EventTest exposing (suite)

import Expect
import Jorn.Event as Event exposing (Error(..))
import Jorn.Html as Html exposing (Html)
import Jorn.Html.Events as Events
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


type Msg
    = Clicked
    | Typed String
    | Child Int


view : Html Msg
view =
    Html.div []
        [ Html.text "header"
        , Html.form []
            [ Html.input [ Events.onInput Typed ] []
            , Html.button [ Events.onClick Clicked ] [ Html.text "go" ]
            ]
        , Html.map Child (Html.button [ Events.onClick 7 ] [])
        ]


incoming : List Int -> String -> Encode.Value -> Event.Incoming
incoming =
    Event.Incoming


noPayload : Encode.Value
noPayload =
    Encode.object []


suite : Test
suite =
    describe "Jorn.Event"
        [ test "routes a click to a nested handler" <|
            \_ ->
                Event.route (incoming [ 1, 1 ] "click" noPayload) view
                    |> Expect.equal (Ok Clicked)
        , test "decodes the included payload" <|
            \_ ->
                Event.route
                    (incoming [ 1, 0 ] "input" (Encode.object [ ( "target", Encode.object [ ( "value", Encode.string "hi" ) ] ) ]))
                    view
                    |> Expect.equal (Ok (Typed "hi"))
        , test "routes through map" <|
            \_ ->
                Event.route (incoming [ 2 ] "click" noPayload) view
                    |> Expect.equal (Ok (Child 7))
        , test "the last handler for an event wins" <|
            \_ ->
                Event.route (incoming [] "click" noPayload)
                    (Html.button [ Events.onClick Clicked, Events.onClick (Child 1) ] [])
                    |> Expect.equal (Ok (Child 1))
        , test "missing node" <|
            \_ ->
                Event.route (incoming [ 9 ] "click" noPayload) view
                    |> Expect.equal (Err (NodeNotFound [ 9 ]))
        , test "negative index is not the first child" <|
            \_ ->
                Event.route (incoming [ -1 ] "click" noPayload) view
                    |> Expect.equal (Err (NodeNotFound [ -1 ]))
        , test "path through a text node" <|
            \_ ->
                Event.route (incoming [ 0, 0 ] "click" noPayload) view
                    |> Expect.equal (Err (NodeNotFound [ 0, 0 ]))
        , test "no handler for that event" <|
            \_ ->
                Event.route (incoming [ 1, 1 ] "input" noPayload) view
                    |> Expect.equal (Err (NoHandler [ 1, 1 ] "input"))
        , test "payload that does not decode" <|
            \_ ->
                case Event.route (incoming [ 1, 0 ] "input" noPayload) view of
                    Err (DecodeFailed "input" _) ->
                        Expect.pass

                    other ->
                        Expect.fail ("expected DecodeFailed, got " ++ Debug.toString other)
        , test "decodes the client message shape" <|
            \_ ->
                """{"path":[1,1],"name":"click","event":{}}"""
                    |> Decode.decodeString Event.decoder
                    |> Result.map (\e -> Event.route e view)
                    |> Expect.equal (Ok (Ok Clicked))
        , test "errors render readably" <|
            \_ ->
                Event.errorToString (NoHandler [ 1, 1 ] "input")
                    |> Expect.equal "No \"input\" handler at path [1,1]"
        ]
