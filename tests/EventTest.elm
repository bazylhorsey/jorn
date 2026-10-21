module EventTest exposing (suite)

import Expect
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
import Jorn.Event as Events
import Jorn.Internal.Event as Event exposing (Error(..))
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


type Msg
    = Clicked
    | Typed String
    | Child Int
    | Submitted (List ( String, String ))
    | Wrapped Msg


view : Element Msg
view =
    Html.div []
        [ Element.text "header"
        , Html.form []
            [ Html.input [ Events.onInput Typed ]
            , Html.button [ Events.onClick Clicked ] [ Element.text "go" ]
            ]
        , Element.map Child (Html.button [ Events.onClick 7 ] [])
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
        , test "routes to a raw element's own handler" <|
            \_ ->
                Event.route (incoming [ 0 ] "click" noPayload) (Html.div [] [ Element.unsafeRawHtml "" "div" [ Events.onClick Clicked ] "<p>hi</p>" ])
                    |> Expect.equal (Ok Clicked)
        , test "never routes into raw content" <|
            \_ ->
                Event.route (incoming [ 0, 0 ] "click" noPayload) (Html.div [] [ Element.unsafeRawHtml "" "div" [ Events.onClick Clicked ] "<p>hi</p>" ])
                    |> Expect.equal (Err (NodeNotFound [ 0, 0 ]))
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
        , test "paths count a fragment's children as the parent's own" <|
            \_ ->
                Event.route (incoming [ 3 ] "click" noPayload)
                    (Html.div []
                        [ Element.none
                        , Element.text "a"
                        , Element.fragment [ Element.text "b", Element.fragment [ Element.none, Element.text "c" ] ]
                        , Element.fragment [ Html.button [ Events.onClick Clicked ] [] ]
                        ]
                    )
                    |> Expect.equal (Ok Clicked)
        , test "routes into a fragment at the root" <|
            \_ ->
                Event.route (incoming [ 1 ] "click" noPayload)
                    (Element.fragment [ Element.text "a", Html.button [ Events.onClick Clicked ] [] ])
                    |> Expect.equal (Ok Clicked)
        , test "a root fragment with one child is that child" <|
            \_ ->
                Event.route (incoming [] "click" noPayload)
                    (Element.fragment [ Element.none, Html.button [ Events.onClick Clicked ] [] ])
                    |> Expect.equal (Ok Clicked)
        , test "routes to keyed children by their position on screen" <|
            \_ ->
                Event.route (incoming [ 1 ] "click" noPayload)
                    (Keyed.ul [] [ ( "b", Html.li [] [] ), ( "a", Html.li [ Events.onClick Clicked ] [] ) ])
                    |> Expect.equal (Ok Clicked)
        , test "keyboard handlers decode the key" <|
            \_ ->
                Event.route (incoming [] "keydown" (Encode.object [ ( "key", Encode.string "Enter" ) ]))
                    (Html.input [ Events.onKeydown Typed ])
                    |> Expect.equal (Ok (Typed "Enter"))
        , test "onChange decodes the committed value" <|
            \_ ->
                Event.route (incoming [] "change" (Encode.object [ ( "target", Encode.object [ ( "value", Encode.string "b" ) ] ) ]))
                    (Html.select [ Events.onChange Typed ] [])
                    |> Expect.equal (Ok (Typed "b"))
        , test "onSubmitFields decodes the form's fields" <|
            \_ ->
                Event.route
                    (incoming [] "submit" (Encode.object [ ( "formFields", Encode.list (Encode.list Encode.string) [ [ "email", "a@b.c" ], [ "plan", "pro" ] ] ) ]))
                    (Html.form [ Events.onSubmitFields Submitted ] [])
                    |> Expect.equal (Ok (Submitted [ ( "email", "a@b.c" ), ( "plan", "pro" ) ]))
        , test "onSubmitFields prevents default and asks the page for the fields" <|
            \_ ->
                Html.form [ Events.onSubmitFields Submitted ] []
                    |> Jorn.Patch.encodeHtml
                    |> Encode.encode 0
                    |> Expect.equal """{"tag":"form","namespace":"","attrs":{},"props":{},"events":{"submit":{"preventDefault":true,"stopPropagation":false,"include":["formFields"]}},"children":[]}"""
        , test "an advanced handler answers with its message and what to prevent" <|
            \_ ->
                [ "Enter", "a", "Escape" ]
                    |> List.map (\k -> Event.decide (incoming [] "keydown" (Encode.object [ ( "key", Encode.string k ) ])) enterOrEscape)
                    |> Expect.equal
                        [ Ok { message = Typed "Enter", preventDefault = True, stopPropagation = False }
                        , Ok { message = Typed "a", preventDefault = False, stopPropagation = False }
                        , Ok { message = Typed "Escape", preventDefault = False, stopPropagation = True }
                        ]
        , test "an advanced handler routes like any other" <|
            \_ ->
                Event.route (incoming [] "keydown" (Encode.object [ ( "key", Encode.string "Enter" ) ])) enterOrEscape
                    |> Expect.equal (Ok (Typed "Enter"))
        , test "other handlers never ask to prevent anything" <|
            \_ ->
                Event.decide (incoming [] "submit" noPayload) (Html.form [ Events.onSubmit Clicked ] [])
                    |> Expect.equal (Ok { message = Clicked, preventDefault = False, stopPropagation = False })
        , test "map keeps an advanced handler's answer" <|
            \_ ->
                Event.decide (incoming [] "keydown" (Encode.object [ ( "key", Encode.string "Enter" ) ])) (Element.map Wrapped enterOrEscape)
                    |> Expect.equal (Ok { message = Wrapped (Typed "Enter"), preventDefault = True, stopPropagation = False })
        , test "an advanced handler tells the page to ask, and options still apply" <|
            \_ ->
                Html.input [ Events.include [ "key" ] (Events.preventDefault (Events.advanced "keydown" (Decode.map (\k -> { message = Typed k, preventDefault = False, stopPropagation = False }) Events.key))) ]
                    |> Jorn.Patch.encodeHtml
                    |> Encode.encode 0
                    |> Expect.equal """{"tag":"input","namespace":"","attrs":{},"props":{},"events":{"keydown":{"preventDefault":true,"stopPropagation":false,"include":["key"],"advanced":true}},"children":[]}"""
        , test "errors render readably" <|
            \_ ->
                Event.errorToString (NoHandler [ 1, 1 ] "input")
                    |> Expect.equal "No \"input\" handler at path [1,1]"
        ]


enterOrEscape : Element Msg
enterOrEscape =
    Html.input
        [ Events.advanced "keydown"
            (Decode.map
                (\k ->
                    { message = Typed k
                    , preventDefault = k == "Enter"
                    , stopPropagation = k == "Escape"
                    }
                )
                Events.key
            )
        ]
