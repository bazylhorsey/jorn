module DiffTest exposing (suite)

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Jorn.Attribute as Attr
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
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
        , keyed
        , raw
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
        , test "none is ignored" <|
            \_ ->
                Jorn.Patch.diff (Html.div [ Attr.id "a" ] []) (Html.div [ Attr.none, Attr.id "a", Attr.none ] [])
                    |> expectPatches []
        , test "style declarations accumulate into one attribute" <|
            \_ ->
                node (Html.div [ Attr.style "color" "red", Attr.styles [ ( "top", "0" ), ( "left", "1px" ) ], Attr.style "color" "blue" ] [])
                    |> Expect.equal (node (Html.div [ Attr.attribute "style" "color: red; top: 0; left: 1px; color: blue" ] []))
        , test "global attributes encode as the HTML spells them" <|
            \_ ->
                node
                    (Html.div
                        [ Attr.data "user-id" "42"
                        , Attr.tabindex -1
                        , Attr.draggable True
                        , Attr.spellcheck False
                        , Attr.translate False
                        , Attr.autocorrect True
                        , Attr.hidden True
                        ]
                        []
                    )
                    |> Expect.equal
                        (node
                            (Html.div
                                [ Attr.attribute "data-user-id" "42"
                                , Attr.attribute "tabindex" "-1"
                                , Attr.attribute "draggable" "true"
                                , Attr.attribute "spellcheck" "false"
                                , Attr.attribute "translate" "no"
                                , Attr.attribute "autocorrect" "on"
                                , Attr.attribute "hidden" ""
                                ]
                                []
                            )
                        )
        , test "boolean global attributes reset live state when false" <|
            \_ ->
                Jorn.Patch.diff (Html.div [ Attr.hidden True ] []) (Html.div [ Attr.hidden False ] [])
                    |> expectPatches [ RemoveAttribute [] "hidden", SetProperty [] "hidden" (Encode.bool False) ]
        , test "element attributes encode as the HTML spells them" <|
            \_ ->
                node (Html.link [ Attr.as_ "font", Attr.crossorigin "anonymous", Attr.width 40, Attr.httpEquiv "refresh", Attr.acceptCharset "utf-8" ])
                    |> Expect.equal
                        (node
                            (Html.link
                                [ Attr.attribute "as" "font"
                                , Attr.attribute "crossorigin" "anonymous"
                                , Attr.attribute "width" "40"
                                , Attr.attribute "http-equiv" "refresh"
                                , Attr.attribute "accept-charset" "utf-8"
                                ]
                            )
                        )
        , test "a boolean attribute resets the DOM property, spelled the DOM's way" <|
            \_ ->
                Jorn.Patch.diff (Html.input [ Attr.readonly True ]) (Html.input [ Attr.readonly False ])
                    |> expectPatches [ RemoveAttribute [] "readonly", SetProperty [] "readOnly" (Encode.bool False) ]
        , test "initial values are properties, so they never control the live state" <|
            \_ ->
                node (Html.input [ Attr.defaultValue "a", Attr.defaultChecked True ])
                    |> Expect.equal (node (Html.input [ Attr.property "defaultValue" (Encode.string "a"), Attr.property "defaultChecked" (Encode.bool True) ]))
        , test "ARIA attributes are aria- attributes with string values" <|
            \_ ->
                node (Html.button [ Attr.role "switch", Attr.ariaChecked "mixed", Attr.ariaLabelledby "a b", Attr.aria "braillelabel" "x" ] [])
                    |> Expect.equal
                        (node
                            (Html.button
                                [ Attr.attribute "role" "switch"
                                , Attr.attribute "aria-checked" "mixed"
                                , Attr.attribute "aria-labelledby" "a b"
                                , Attr.attribute "aria-braillelabel" "x"
                                ]
                                []
                            )
                        )
        , test "property change" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.element "data-grid" [ Attr.property "rows" (Encode.int 1) ] [])
                    (Element.element "data-grid" [ Attr.property "rows" (Encode.int 2) ] [])
                    |> expectPatches [ SetProperty [] "rows" (Encode.int 2) ]
        , test "value is an attribute" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Attr.value "a" ])
                    (Html.input [ Attr.value "b" ])
                    |> expectPatches [ SetAttribute [] "value" "b" ]
        , test "boolean attributes switch between attribute and false property" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Attr.checked True ])
                    (Html.input [ Attr.checked False ])
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
                Jorn.Patch.diff (Html.input [ Attr.checked False ]) (Html.input [])
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
                        [ SetEvent [] "submit" { preventDefault = True, stopPropagation = False, include = [], debounce = 0, throttle = 0, advanced = False } ]
        , test "an option reaches only the handler it wraps" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.preventDefault (Events.onClick ()), Events.onInput (\_ -> ()) ] [])
                    |> expectPatches
                        [ SetEvent [] "click" { preventDefault = True, stopPropagation = False, include = [], debounce = 0, throttle = 0, advanced = False }
                        , SetEvent [] "input" { preventDefault = False, stopPropagation = False, include = [ "target.value" ], debounce = 0, throttle = 0, advanced = False }
                        ]
        , test "options on one handler merge rather than replace each other" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.include [ "target.value" ] (Events.stopPropagation (Events.onClick ())) ] [])
                    |> expectPatches
                        [ SetEvent [] "click" { preventDefault = False, stopPropagation = True, include = [ "target.value" ], debounce = 0, throttle = 0, advanced = False } ]
        , test "debounce and throttle merge to the longest asked for" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.debounce 100 (Events.throttle 500 (Events.debounce 300 (Events.preventDefault (Events.onClick ())))) ] [])
                    |> expectPatches
                        [ SetEvent [] "click" { preventDefault = True, stopPropagation = False, include = [], debounce = 300, throttle = 500, advanced = False } ]
        , test "a changed debounce is re-sent" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Events.debounce 100 (Events.onInput identity) ])
                    (Html.input [ Events.debounce 200 (Events.onInput identity) ])
                    |> expectPatches
                        [ SetEvent [] "input" { preventDefault = False, stopPropagation = False, include = [ "target.value" ], debounce = 200, throttle = 0, advanced = False } ]
        , test "making a handler advanced re-sends its options" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [ Events.onKeydown identity ])
                    (Html.input [ Events.include [ "key" ] (Events.advanced "keydown" (Decode.map (\k -> { message = k, preventDefault = k == "Enter", stopPropagation = False }) Events.key)) ])
                    |> expectPatches
                        [ SetEvent [] "keydown" { preventDefault = False, stopPropagation = False, include = [ "key" ], debounce = 0, throttle = 0, advanced = True } ]
        , test "an option around something that is not a handler is ignored" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [])
                    (Html.div [ Events.preventDefault (Attr.id "x") ] [])
                    |> expectPatches [ SetAttribute [] "id" "x" ]
        , test "event helpers ask for exactly the fields they decode" <|
            \_ ->
                node (Html.input [ Events.onKeydown identity, Events.onChange identity, Events.onFocus "f", Events.onMouseEnter "e" ])
                    |> Expect.equal
                        (node
                            (Html.input
                                [ Events.include [ "key" ] (Events.on "keydown" (Decode.succeed ""))
                                , Events.include [ "target.value" ] (Events.on "change" (Decode.succeed ""))
                                , Events.on "focus" (Decode.succeed "")
                                , Events.on "mouseenter" (Decode.succeed "")
                                ]
                            )
                        )
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
        , test "none leaves nothing behind" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.text "a" ])
                    (Html.div [] [ Element.none, Element.text "a", Element.none ])
                    |> expectPatches []
        , test "a fragment's children are spliced into the parent's" <|
            \_ ->
                node (Html.ul [] [ Html.li [] [], Element.fragment [ Html.li [] [], Element.fragment [ Html.li [] [] ] ], Html.li [] [] ])
                    |> Expect.equal (node (Html.ul [] [ Html.li [] [], Html.li [] [], Html.li [] [], Html.li [] [] ]))
        , test "a fragment growing shifts the siblings after it" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.fragment [ Element.text "a" ], Element.text "z" ])
                    (Html.div [] [ Element.fragment [ Element.text "a", Element.text "b" ], Element.text "z" ])
                    |> expectPatches [ SetText [ 1 ] "b", Append [] [ node (Element.text "z") ] ]
        , test "none at the root is an empty text node" <|
            \_ ->
                node Element.none
                    |> Expect.equal (Vdom.NodeText "")
        , test "a root fragment with one child is that child" <|
            \_ ->
                Jorn.Patch.diff (Html.div [] []) (Element.fragment [ Element.none, Html.div [] [] ])
                    |> expectPatches []
        , test "a root fragment with several children gets a layout-free wrapper" <|
            \_ ->
                node (Element.fragment [ Element.text "a", Element.text "b" ])
                    |> Expect.equal (node (Element.element "jorn-fragment" [ Attr.attribute "style" "display: contents" ] [ Element.text "a", Element.text "b" ]))
        , test "how an element closes never produces a patch" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.element "br" [] [])
                    (Element.advanced { namespace = "", tag = "br", closing = Element.Void } [] [])
                    |> expectPatches []
        , test "map produces no patches when only messages change" <|
            \_ ->
                let
                    view =
                        Html.button [ Events.onClick 1 ] [ Element.text "+" ]
                in
                Jorn.Patch.diff (Element.map String.fromInt view) (Element.map (\n -> String.fromInt (n + 1)) view)
                    |> expectPatches []
        ]


keyed : Test
keyed =
    let
        items keys =
            Keyed.ul [] (List.map (\k -> ( k, Html.li [] [ Element.text k ] )) keys)

        count predicate patches =
            List.length (List.filter predicate patches)

        isMove patch =
            case patch of
                Move _ _ _ ->
                    True

                _ ->
                    False

        structural patch =
            case patch of
                Move _ _ _ ->
                    True

                Insert _ _ _ ->
                    True

                Remove _ _ ->
                    True

                _ ->
                    False
    in
    describe "keyed children"
        [ test "the same keys in the same order produce no patches" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "b", "c" ]) (items [ "a", "b", "c" ])
                    |> expectPatches []
        , test "removing the first item is one remove, not a rewrite" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "b", "c", "d" ]) (items [ "b", "c", "d" ])
                    |> expectPatches [ Remove [] 0 ]
        , test "inserting in the middle is one insert" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "c" ]) (items [ "a", "b", "c" ])
                    |> expectPatches [ Insert [] 1 (node (Html.li [] [ Element.text "b" ])) ]
        , test "moving the first item to the end is one move" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "b", "c", "d", "e" ]) (items [ "b", "c", "d", "e", "a" ])
                    |> expectPatches [ Move [] 0 4 ]
        , test "moving the last item to the front is one move" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "b", "c", "d", "e" ]) (items [ "e", "a", "b", "c", "d" ])
                    |> expectPatches [ Move [] 4 0 ]
        , test "swapping two items moves only those that must move" <|
            \_ ->
                Jorn.Patch.diff (items [ "a", "b", "c", "d", "e" ]) (items [ "a", "d", "c", "b", "e" ])
                    |> count isMove
                    |> Expect.equal 2
        , test "reversing n items takes n - 1 moves" <|
            \_ ->
                let
                    keys =
                        List.map String.fromInt (List.range 1 50)
                in
                Jorn.Patch.diff (items keys) (items (List.reverse keys))
                    |> count isMove
                    |> Expect.equal 49
        , test "a moved item is diffed at its new position" <|
            \_ ->
                Jorn.Patch.diff
                    (Keyed.ul [] [ ( "a", Element.text "1" ), ( "b", Element.text "2" ) ])
                    (Keyed.ul [] [ ( "b", Element.text "2" ), ( "a", Element.text "one" ) ])
                    |> expectPatches [ Move [] 1 0, SetText [ 1 ] "one" ]
        , test "duplicate keys match in order" <|
            \_ ->
                Jorn.Patch.diff
                    (Keyed.ul [] [ ( "x", Element.text "1" ), ( "x", Element.text "2" ) ])
                    (Keyed.ul [] [ ( "x", Element.text "1" ), ( "x", Element.text "2" ), ( "x", Element.text "3" ) ])
                    |> expectPatches [ Insert [] 2 (node (Element.text "3")) ]
        , test "unkeyed children among keyed ones match by their own order" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.ul [] [ Element.text "header", Keyed.fragment [ ( "a", Element.text "a" ), ( "b", Element.text "b" ) ] ])
                    (Html.ul [] [ Element.text "header", Keyed.fragment [ ( "b", Element.text "b" ), ( "a", Element.text "a" ) ] ])
                    |> count structural
                    |> Expect.equal 1
        , test "a changed tag under the same key is replaced in place" <|
            \_ ->
                Jorn.Patch.diff
                    (Keyed.div [] [ ( "a", Html.p [] [] ), ( "b", Html.p [] [] ) ])
                    (Keyed.div [] [ ( "b", Html.p [] [] ), ( "a", Html.span [] [] ) ])
                    |> expectPatches [ Move [] 1 0, Replace [ 1 ] (node (Html.span [] [])) ]
        , test "keys never reach the wire" <|
            \_ ->
                Vdom.toNode (items [ "b", "a" ])
                    |> Expect.equal (Vdom.toNode (Html.ul [] [ Html.li [] [ Element.text "b" ], Html.li [] [ Element.text "a" ] ]))
        , fuzz2 (Fuzz.list (Fuzz.oneOfValues [ "a", "b", "c", "d", "e", "f" ])) (Fuzz.list (Fuzz.oneOfValues [ "a", "b", "c", "d", "e", "f" ])) "any reordering round-trips" <|
            \a b ->
                Reference.apply (Jorn.Patch.diff (items a) (items b)) (Vdom.toNode (items a))
                    |> Maybe.map Reference.render
                    |> Expect.equal (Just (Reference.render (Vdom.toNode (items b))))
        ]


{-| Pins the wire format. If this test changes, the protocol changed, and the
JS client and PROTOCOL.md have to change with it.
-}
raw : Test
raw =
    describe "raw HTML"
        [ test "the same HTML produces no patches" <|
            \_ ->
                let
                    tree =
                        Element.unsafeRawHtml "" "div" [ Attr.class "a" ] "<p>hi</p>"
                in
                Jorn.Patch.diff tree tree |> expectPatches []
        , test "changed HTML is set as a whole" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.unsafeRawHtml "" "div" [] "<p>a</p>" ])
                    (Html.div [] [ Element.unsafeRawHtml "" "div" [] "<p>b</p>" ])
                    |> expectPatches [ SetHtml [ 0 ] "<p>b</p>" ]
        , test "the element's own attributes are diffed as usual" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.unsafeRawHtml "" "div" [ Attr.class "a" ] "x")
                    (Element.unsafeRawHtml "" "div" [ Attr.class "b" ] "x")
                    |> expectPatches [ SetAttribute [] "class" "b" ]
        , test "a raw element and an ordinary one replace each other" <|
            \_ ->
                let
                    plain =
                        Html.div [] [ Element.text "x" ]

                    rawDiv =
                        Element.unsafeRawHtml "" "div" [] "x"
                in
                ( Jorn.Patch.diff plain rawDiv, Jorn.Patch.diff rawDiv plain )
                    |> Expect.all
                        [ Tuple.first >> expectPatches [ Replace [] (node rawDiv) ]
                        , Tuple.second >> expectPatches [ Replace [] (node plain) ]
                        ]
        , test "a different tag replaces" <|
            \_ ->
                Jorn.Patch.diff
                    (Element.unsafeRawHtml "" "div" [] "x")
                    (Element.unsafeRawHtml "" "span" [] "x")
                    |> expectPatches [ Replace [] (node (Element.unsafeRawHtml "" "span" [] "x")) ]
        , test "the reference patcher rejects patches aimed inside raw content" <|
            \_ ->
                Reference.apply [ Append [] [ node (Element.text "x") ] ] (node (Element.unsafeRawHtml "" "div" [] "<p>a</p>"))
                    |> Expect.equal Nothing
        ]


wire : Test
wire =
    describe "wire format"
        [ test "golden patch encoding" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [ Attr.id "root" ] [ Element.text "a", Html.input [] ])
                    (Html.div [ Attr.id "root" ] [ Element.text "b", Html.input [ Events.onInput identity ], Html.span [ Attr.class "x" ] [] ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        ("["
                            ++ """{"op":"set-text","path":[0],"text":"b"},"""
                            ++ """{"op":"set-event","path":[1],"name":"input","options":{"preventDefault":false,"stopPropagation":false,"include":["target.value"]}},"""
                            ++ """{"op":"append","path":[],"nodes":[{"tag":"span","namespace":"","attrs":{"class":"x"},"props":{},"events":{},"children":[]}]}"""
                            ++ "]"
                        )
        , test "golden advanced handler encoding" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.input [])
                    (Html.input [ Events.advanced "keydown" (Decode.succeed { message = (), preventDefault = True, stopPropagation = False }) ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        """[{"op":"set-event","path":[],"name":"keydown","options":{"preventDefault":false,"stopPropagation":false,"include":[],"advanced":true}}]"""
        , test "golden fragment encoding: fragments never reach the wire" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.fragment [ Element.text "a" ] ])
                    (Html.div [] [ Element.none, Element.fragment [ Element.text "a", Element.fragment [ Html.span [] [] ] ] ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        """[{"op":"append","path":[],"nodes":[{"tag":"span","namespace":"","attrs":{},"props":{},"events":{},"children":[]}]}]"""
        , test "golden keyed encoding" <|
            \_ ->
                Jorn.Patch.diff
                    (Keyed.ul [] [ ( "a", Html.li [] [] ), ( "b", Html.li [] [] ), ( "c", Html.li [] [] ) ])
                    (Keyed.ul [] [ ( "c", Html.li [] [] ), ( "a", Html.li [] [] ), ( "d", Element.text "d" ) ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        ("["
                            ++ """{"op":"remove","path":[],"index":1},"""
                            ++ """{"op":"insert","path":[],"index":2,"node":{"text":"d"}},"""
                            ++ """{"op":"move","path":[],"from":1,"to":0}"""
                            ++ "]"
                        )
        , test "golden mount encoding" <|
            \_ ->
                Html.button [ Attr.disabled True, Events.onClick () ] [ Element.text "go" ]
                    |> Jorn.Patch.encodeHtml
                    |> Encode.encode 0
                    |> Expect.equal
                        """{"tag":"button","namespace":"","attrs":{"disabled":""},"props":{},"events":{"click":{"preventDefault":false,"stopPropagation":false,"include":[]}},"children":[{"text":"go"}]}"""
        , test "golden raw HTML encoding" <|
            \_ ->
                Jorn.Patch.diff
                    (Html.div [] [ Element.unsafeRawHtml "" "div" [] "<p>a</p>" ])
                    (Html.div [] [ Element.unsafeRawHtml "" "div" [] "<p>b</p>", Element.unsafeRawHtml "" "section" [ Attr.class "x" ] "<b>c</b>" ])
                    |> Jorn.Patch.encode
                    |> Encode.encode 0
                    |> Expect.equal
                        ("["
                            ++ """{"op":"set-html","path":[0],"html":"<p>b</p>"},"""
                            ++ """{"op":"append","path":[],"nodes":[{"tag":"section","namespace":"","attrs":{"class":"x"},"props":{},"events":{},"html":"<b>c</b>"}]}"""
                            ++ "]"
                        )
        , test "golden debounce and throttle encoding" <|
            \_ ->
                Html.input [ Events.debounce 300 (Events.onInput identity), Events.throttle 100 (Events.on "scroll" (Decode.succeed "")) ]
                    |> Jorn.Patch.encodeHtml
                    |> Encode.encode 0
                    |> Expect.equal
                        """{"tag":"input","namespace":"","attrs":{},"props":{},"events":{"input":{"preventDefault":false,"stopPropagation":false,"include":["target.value"],"debounce":300},"scroll":{"preventDefault":false,"stopPropagation":false,"include":[],"throttle":100}},"children":[]}"""
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
              , Fuzz.map4 (\ns tag -> Vdom.Element ns tag Vdom.Normal)
                    (Fuzz.oneOfValues [ "", "", "svg-ns" ])
                    (Fuzz.oneOfValues [ "div", "span", "li" ])
                    (Fuzz.listOfLengthBetween 0 4 attribute)
                    (Fuzz.listOfLengthBetween 0 3 (html (depth - 1)))
              )
            , ( 1, Fuzz.map Element.fragment (Fuzz.listOfLengthBetween 0 3 (html (depth - 1))) )
            , ( 1
              , Fuzz.map3 (Element.unsafeRawHtml "")
                    (Fuzz.oneOfValues [ "div", "span" ])
                    (Fuzz.listOfLengthBetween 0 2 attribute)
                    (Fuzz.oneOfValues [ "", "a", "<i>a</i>" ])
              )
            , ( 2
              , Fuzz.map2 (Vdom.Element "" "ul" Vdom.Normal)
                    (Fuzz.listOfLengthBetween 0 2 attribute)
                    (Fuzz.listOfLengthBetween 0 5 (keyedChild (depth - 1)))
              )
            ]


{-| Mostly keyed, from a small alphabet so keys repeat and lists overlap, with
the odd unkeyed child mixed in.
-}
keyedChild : Int -> Fuzzer (Element String)
keyedChild depth =
    Fuzz.frequency
        [ ( 6, Fuzz.map2 Vdom.Keyed (Fuzz.oneOfValues [ "a", "b", "c", "d" ]) (html depth) )
        , ( 1, html depth )
        ]


{-| Options are functions, so pick them from a set rather than build one.
-}
options : Fuzzer (Events.Options String)
options =
    Fuzz.oneOfValues [ identity, Events.preventDefault, Events.stopPropagation ]


attribute : Fuzzer (Attr.Attribute String)
attribute =
    Fuzz.oneOf
        [ Fuzz.constant Attr.none
        , Fuzz.map2 Attr.style (Fuzz.oneOfValues [ "color", "top" ]) (Fuzz.oneOfValues [ "", "red" ])
        , Fuzz.map2 Attr.attribute (Fuzz.oneOfValues [ "id", "title", "class" ]) (Fuzz.oneOfValues [ "", "x", "y" ])
        , Fuzz.map Attr.value (Fuzz.oneOfValues [ "", "v" ])
        , Fuzz.map Attr.checked Fuzz.bool
        , Fuzz.map (\items -> Attr.property "config" (Encode.list Encode.int items)) (Fuzz.listOfLengthBetween 0 2 (Fuzz.intRange 0 2))
        , Fuzz.map2
            (\name opts -> Events.custom name opts (Decode.succeed name))
            (Fuzz.oneOfValues [ "click", "input" ])
            options
        ]
