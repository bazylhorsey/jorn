module ServerComponentTest exposing (suite)

import Expect
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Event
import Jorn.Patch
import Jorn.ServerComponent as ServerComponent exposing (Error(..))
import Json.Encode as Encode
import Test exposing (Test, describe, test)


type Msg
    = Clicked
    | Typed String


view : Element Msg
view =
    Html.div []
        [ Html.input [ Event.onInput Typed ]
        , Html.button [ Event.onClick Clicked ] [ Element.text "go" ]
        ]


event : List Int -> String -> Encode.Value -> Encode.Value
event path name payload =
    Encode.object
        [ ( "path", Encode.list Encode.int path )
        , ( "name", Encode.string name )
        , ( "event", payload )
        ]


encode : Element msg -> String
encode element =
    Encode.encode 0 (Jorn.Patch.encodeHtml element)


suite : Test
suite =
    describe "Jorn.ServerComponent"
        [ describe "element"
            [ test "is a jorn-server-component with its route, flags and token" <|
                \_ ->
                    ServerComponent.element
                        [ ServerComponent.route "/chat"
                        , ServerComponent.flags (Encode.object [ ( "room", Encode.string "elm" ) ])
                        , ServerComponent.csrfToken "abc"
                        ]
                        |> encode
                        |> Expect.equal """{"tag":"jorn-server-component","namespace":"","attrs":{"csrf-token":"abc","flags":"{\\"room\\":\\"elm\\"}","route":"/chat"},"props":{},"events":{},"children":[]}"""
            , test "script imports the client and defines the element" <|
                \_ ->
                    ServerComponent.script "/jorn.js"
                        |> encode
                        |> Expect.equal """{"tag":"script","namespace":"","attrs":{"type":"module"},"props":{},"events":{},"children":[{"text":"import { defineServerComponent } from \\"/jorn.js\\";\\ndefineServerComponent();"}]}"""
            , test "script can't be closed early by its address" <|
                \_ ->
                    ServerComponent.script "/a</script><b>"
                        |> encode
                        |> String.contains "</script>"
                        |> Expect.equal False
            ]
        , describe "decodeEvent"
            [ test "routes an event to its handler" <|
                \_ ->
                    event [ 0 ] "input" (Encode.object [ ( "target", Encode.object [ ( "value", Encode.string "hi" ) ] ) ])
                        |> ServerComponent.decodeEvent view
                        |> Expect.equal (Ok (Typed "hi"))
            , test "a click" <|
                \_ ->
                    event [ 1 ] "click" (Encode.object [])
                        |> ServerComponent.decodeEvent view
                        |> Expect.equal (Ok Clicked)
            , test "something that isn't an event" <|
                \_ ->
                    case ServerComponent.decodeEvent view (Encode.object [ ( "path", Encode.string "nope" ) ]) of
                        Err (NotAnEvent _) ->
                            Expect.pass

                        other ->
                            Expect.fail (Debug.toString other)
            , test "nothing at the path" <|
                \_ ->
                    event [ 5 ] "click" (Encode.object [])
                        |> ServerComponent.decodeEvent view
                        |> Expect.equal (Err (NodeNotFound [ 5 ]))
            , test "nothing handles it" <|
                \_ ->
                    event [ 1 ] "input" (Encode.object [])
                        |> ServerComponent.decodeEvent view
                        |> Expect.equal (Err (NoHandler [ 1 ] "input"))
            , test "the handler can't read it, and says so" <|
                \_ ->
                    case ServerComponent.decodeEvent view (event [ 0 ] "input" (Encode.object [])) of
                        Err ((HandlerFailed "input" _) as error) ->
                            ServerComponent.errorToString error
                                |> String.startsWith "The \"input\" handler failed to decode"
                                |> Expect.equal True

                        other ->
                            Expect.fail (Debug.toString other)
            ]
        ]
