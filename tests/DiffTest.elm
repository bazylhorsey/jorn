module DiffTest exposing (suite)

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Jorn.Attribute as Attr
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Event as Events
import Jorn.Internal.Patch exposing (Patch(..))
import Jorn.Internal.Vdom as Vdom
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode
import Reference
import Test exposing (Test, describe, fuzz, fuzz2, test)


suite : Test
suite =
    describe "Jorn.Patch.diff"
        [ unit
        , wire
        , properties
        ]


{-| Patches hold JSON values, so compare canonical encodings.
-}
expectPatches : List Patch -> List Patch -> Expectation
expectPatches expected actual =
    Expect.equal
        (Encode.encode 2 (Jorn.Patch.encode expected))
        (Encode.encode 2 (Jorn.Patch.encode actual))


node : Element msg -> Vdom.Node
node =
    Vdom.toNode


unit : Test
unit =
    describe "unit"
        [ test "identical trees produce no patches" <|
            \_ ->
                let
                    tree =
                        Html.div [ Attr.class "a", Events.onClick () ] [ Element.text "hi" ]
                in
                Jorn.Patch.diff tree tree |> expectPatches []
        , test "changed text" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.text "a" ])
                    (Html.div [] [ Element.text "b" ])
                    |> expectPatches [ SetText [ 0 ] "b" ]
        , test "changed tag replaces" <|
            \_ ->
                Jorn.Patch.diff (Html.div [] []) (Html.span [] [])
                    |> expectPatches [ Replace [] (node (Html.span [] [])) ]
        , test "changed namespace replaces" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.element "svg" [] [])
                    (Element.namespaced "http://www.w3.org/2000/svg" "svg" [] [])
                    |> expectPatches [ Replace [] (node (Element.namespaced "http://www.w3.org/2000/svg" "svg" [] [])) ]
        , test "text to element replaces" <|
            \_ ->
                Jorn.Patch.diff (Html.div [] [ Element.text "x" ]) (Html.div [] [ Html.p [] [] ])
                    |> expectPatches [ Replace [ 0 ] (node (Html.p [] [])) ]
        , test "attributes added, changed, removed" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [ Attr.id "a", Attr.href "/x" ] [])
                    (Html.div [ Attr.id "b", Attr.placeholder "p" ] [])
                    |> expectPatches
                        [ RemoveAttribute [] "href"
                        , SetAttribute [] "id" "b"
                        , SetAttribute [] "placeholder" "p"
                        ]
        , test "multiple classes merge" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [ Attr.class "a" ] [])
                    (Html.div [ Attr.class "a", Attr.classes [ ( "b", True ), ( "c", False ) ] ] [])
                    |> expectPatches [ SetAttribute [] "class" "a b" ]
        , test "property change" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.element "data-grid" [ Attr.property "rows" (Encode.int 1) ] [])
                    (Element.element "data-grid" [ Attr.property "rows" (Encode.int 2) ] [])
                    |> expectPatches [ SetProperty [] "rows" (Encode.int 2) ]
        , test "value is an attribute" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Attr.value "a" ] [])
                    (Html.input [ Attr.value "b" ] [])
                    |> expectPatches [ SetAttribute [] "value" "b" ]
        , test "boolean attributes switch between attribute and false property" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Attr.checked True ] [])
                    (Html.input [ Attr.checked False ] [])
                    |> expectPatches
                        [ RemoveAttribute [] "checked"
                        , SetProperty [] "checked" (Encode.bool False)
                        ]
        , test "structurally equal object properties produce no patch" <|
            \_ ->
                let
                    config =
                        Encode.object [ ( "rows", Encode.list Encode.int [ 1, 2 ] ) ]
                in
                Jorn.Patch.diff
                    (Element.element "data-grid" [ Attr.property "config" config ] [])
                    (Element.element "data-grid" [ Attr.property "config" (Encode.object [ ( "rows", Encode.list Encode.int [ 1, 2 ] ) ]) ] [])
                    |> expectPatches []
        , test "removed property" <|
            \_ ->
                Jorn.Patch.diff (Html.input [ Attr.checked False ] []) (Html.input [] [])
                    |> expectPatches [ RemoveProperty [] "checked" ]
        , test "event added and removed" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.button [ Events.onClick () ] [])
                    (Html.button [ Events.on "mouseover" (Decode.succeed ()) ] [])
                    |> expectPatches
                        [ RemoveEvent [] "click"
                        , SetEvent [] "mouseover" Vdom.defaultOptions
                        ]
        , test "a handler with a different message but the same options needs no patch" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.button [ Events.onClick 1 ] [])
                    (Html.button [ Events.onClick 2 ] [])
                    |> expectPatches []
        , test "changed event options are re-sent" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.form [ Events.on "submit" (Decode.succeed ()) ] [])
                    (Html.form [ Events.preventDefault (Events.onSubmit ()) ] [])
                    |> expectPatches
                        [ SetEvent [] "submit" { preventDefault = True, stopPropagation = False, include = [] } ]
        , test "an option reaches only the handler it wraps" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.preventDefault (Events.onClick ()), Events.onInput (\_ -> ()) ] [])
                    |> expectPatches
                        [ SetEvent [] "click" { preventDefault = True, stopPropagation = False, include = [] }
                        , SetEvent [] "input" { preventDefault = False, stopPropagation = False, include = [ "target.value" ] }
                        ]
        , test "options on one handler merge rather than replace each other" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.include [ "target.value" ] (Events.stopPropagation (Events.onClick ())) ] [])
                    |> expectPatches
                        [ SetEvent [] "click" { preventDefault = False, stopPropagation = True, include = [ "target.value" ] } ]
        , test "an option around something that is not a handler is ignored" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.preventDefault (Attr.id "x") ] [])
                    |> expectPatches [ SetAttribute [] "id" "x" ]
        , test "children appended" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.ul [] [ Html.li [] [] ])
                    (Html.ul [] [ Html.li [] [], Html.li [] [ Element.text "2" ], Html.li [] [] ])
                    |> expectPatches [ Append [] [ node (Html.li [] [ Element.text "2" ]), node (Html.li [] []) ] ]
        , test "children truncated, after patches to surviving children" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.ul [] [ Html.li [] [ Element.text "a" ], Html.li [] [], Html.li [] [] ])
                    (Html.ul [] [ Html.li [] [ Element.text "b" ] ])
                    |> expectPatches [ SetText [ 0, 0 ] "b", Truncate [] 1 ]
        , test "deep paths" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Html.p [] [], Html.ul [] [ Html.li [] [], Html.li [] [ Element.text "old" ] ] ])
                    (Html.div [] [ Html.p [] [], Html.ul [] [ Html.li [] [], Html.li [] [ Element.text "new" ] ] ])
                    |> expectPatches [ SetText [ 1, 1, 0 ] "new" ]
        , test "map produces no patches when only messages change" <|
            \_ ->
                let
                    view =
                        Html.button [ Events.onClick 1 ] [ Element.text "+" ]
                in
                Jorn.Patch.diff (Element.map String.fromInt view) (Element.map (\n -> String.fromInt (n + 1)) view)
                    |> expectPatches []
        ]


{-| Pins the wire format. If this test changes, the protocol changed, and the
JS client and PROTOCOL.md have to change with it.
-}
wire : Test
wire =
    describe "wire format"
        [ test "golden patch encoding" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [ Attr.id "root" ] [ Element.text "a", Html.input [] [] ])
                    (Html.div [ Attr.id "root" ] [ Element.text "b", Html.input [ Events.onInput identity ] [], Html.span [ Attr.class "x" ] [] ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        ("["
                            ++ """{"op":"set-text","path":[0],"text":"b"},"""
                            ++ """{"op":"set-event","path":[1],"name":"input","options":{"preventDefault":false,"stopPropagation":false,"include":["target.value"]}},"""
                            ++ """{"op":"append","path":[],"nodes":[{"tag":"span","namespace":"","attrs":{"class":"x"},"props":{},"events":{},"children":[]}]}"""
                            ++ "]"
                        )
        , test "golden mount encoding" <|
            \_ ->
                Html.button [ Attr.disabled True, Events.onClick () ] [ Element.text "go" ]
                    |> Jorn.Patch.encodeHtml
                    |> Encode.encode 0
                    |> Expect.equal
                        """{"tag":"button","namespace":"","attrs":{"disabled":""},"props":{},"events":{"click":{"preventDefault":false,"stopPropagation":false,"include":[]}},"children":[{"text":"go"}]}"""
        ]



-- PROPERTIES


properties : Test
properties =
    describe "properties"
        [ fuzz2 (html 4) (html 4) "applying diff a b to a yields b" <|
            \a b ->
                Reference.apply (Jorn.Patch.diff a b) (Vdom.toNode a)
                    |> Maybe.map Reference.render
                    |> Expect.equal (Just (Reference.render (Vdom.toNode b)))
        , fuzz (html 4) "diffing a tree against itself is empty" <|
            \a ->
                Jorn.Patch.diff a a |> expectPatches []
        , fuzz2 (html 3) (html 3) "the round trip holds through map" <|
            \a b ->
                let
                    ma =
                        Element.map String.length a

                    mb =
                        Element.map String.length b
                in
                Reference.apply (Jorn.Patch.diff ma mb) (Vdom.toNode ma)
                    |> Maybe.map Reference.render
                    |> Expect.equal (Just (Reference.render (Vdom.toNode mb)))
        ]


{-| Small alphabets on purpose: collisions between the two trees are what
exercise the interesting branches.
-}
html : Int -> Fuzzer (Element String)
html depth =
    let
        textNode =
            Fuzz.map Element.text (Fuzz.oneOfValues [ "", "a", "b" ])
    in
    if depth <= 0 then
        textNode

    else
        Fuzz.frequency
            [ ( 1, textNode )
            , ( 3
              , Fuzz.map4 Vdom.Element
                    (Fuzz.oneOfValues [ "", "", "svg-ns" ])
                    (Fuzz.oneOfValues [ "div", "span", "li" ])
                    (Fuzz.listOfLengthBetween 0 4 attribute)
                    (Fuzz.listOfLengthBetween 0 3 (html (depth - 1)))
              )
            ]


{-| Options are functions, so pick them from a set rather than build one.
-}
options : Fuzzer (Events.Options String)
options =
    Fuzz.oneOfValues [ identity, Events.preventDefault, Events.stopPropagation ]


attribute : Fuzzer (Attr.Attribute String)
attribute =
    Fuzz.oneOf
        [ Fuzz.map2 Attr.attribute (Fuzz.oneOfValues [ "id", "title", "class" ]) (Fuzz.oneOfValues [ "", "x", "y" ])
        , Fuzz.map Attr.value (Fuzz.oneOfValues [ "", "v" ])
        , Fuzz.map Attr.checked Fuzz.bool
        , Fuzz.map (\items -> Attr.property "config" (Encode.list Encode.int items)) (Fuzz.listOfLengthBetween 0 2 (Fuzz.intRange 0 2))
        , Fuzz.map2
            (\name opts -> Events.custom name opts (Decode.succeed name))
            (Fuzz.oneOfValues [ "click", "input" ])
            options
        ]
