module StringTest exposing (suite)

import Expect
import Jorn.Attribute as Attr
import Jorn.Element as Element
import Jorn.Element.Html as Html
import Jorn.Element.Keyed as Keyed
import Jorn.Element.Svg as Svg
import Jorn.Event as Events
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Element.toString"
        [ escaping
        , elements
        , attributes
        , structure
        , readable
        ]


escaping : Test
escaping =
    describe "escaping"
        [ test "text" <|
            \_ ->
                Html.p [] [ Element.text "<b> & \"c\" 'd'\u{00A0}" ]
                    |> Element.toString
                    |> Expect.equal "<p>&lt;b&gt; &amp; \"c\" 'd'&nbsp;</p>"
        , test "attribute values" <|
            \_ ->
                Html.a [ Attr.title "\"quoted\" & <tagged>" ] []
                    |> Element.toString
                    |> Expect.equal "<a title=\"&quot;quoted&quot; &amp; &lt;tagged&gt;\"></a>"
        , test "script and style text is written as it is, except a closing tag" <|
            \_ ->
                Html.div []
                    [ Html.script [] [ Element.text "if (a < b && c) { x = \"</script>\" }" ]
                    , Html.style [] [ Element.text "a > b { color: red }" ]
                    ]
                    |> Element.toString
                    |> Expect.equal "<div><script>if (a < b && c) { x = \"<\\/script>\" }</script><style>a > b { color: red }</style></div>"
        , test "SVG style text is escaped, since the browser parses it" <|
            \_ ->
                Svg.svg [] [ Svg.style [] [ Element.text "a > b {}" ] ]
                    |> Element.toString
                    |> Expect.equal "<svg><style>a &gt; b {}</style></svg>"
        , test "names that would break out of a tag are left out" <|
            \_ ->
                Html.div [ Attr.attribute "onclick=\"steal()\" x" "1", Attr.attribute "" "2", Attr.id "ok" ]
                    [ Element.element "img src=x onerror=steal()" [] [], Element.element "b" [] [] ]
                    |> Element.toString
                    |> Expect.equal "<div id=\"ok\"><b></b></div>"
        ]


elements : Test
elements =
    describe "elements"
        [ test "void elements have no closing tag" <|
            \_ ->
                Html.div [] [ Html.br [], Html.input [ Attr.type_ "text" ], Html.img [ Attr.src "a.png", Attr.alt "" ] ]
                    |> Element.toString
                    |> Expect.equal "<div><br><input type=\"text\"><img alt=\"\" src=\"a.png\"></div>"
        , test "self-closing elements close themselves when empty" <|
            \_ ->
                Element.advanced { namespace = Svg.namespace, tag = "path", closing = Element.SelfClosing } [ Attr.attribute "d" "M0 0" ] []
                    |> Element.toString
                    |> Expect.equal "<path d=\"M0 0\" />"
        , test "SVG and MathML elements" <|
            \_ ->
                Html.div [] [ Svg.svg [] [ Svg.circle [ Attr.attribute "r" "1" ] [] ], Html.math [] [] ]
                    |> Element.toString
                    |> Expect.equal "<div><svg><circle r=\"1\"></circle></svg><math></math></div>"
        , test "raw HTML is written as it is" <|
            \_ ->
                Element.unsafeRawHtml "" "article" [ Attr.class "post" ] "<p>Hi & <em>bye</em></p>"
                    |> Element.toString
                    |> Expect.equal "<article class=\"post\"><p>Hi & <em>bye</em></p></article>"
        , test "a textarea's value is its content" <|
            \_ ->
                Html.textarea [ Attr.value "a < b", Attr.name "note" ] []
                    |> Element.toString
                    |> Expect.equal "<textarea name=\"note\">a &lt; b</textarea>"
        , test "a whole page" <|
            \_ ->
                Html.html [] [ Html.head [] [ Html.title [] [ Element.text "Jorn" ] ], Html.body [] [ Element.text "Hello" ] ]
                    |> Element.toDocumentString
                    |> Expect.equal "<!doctype html><html><head><title>Jorn</title></head><body>Hello</body></html>"
        ]


attributes : Test
attributes =
    describe "attributes"
        [ test "true boolean attributes are empty, and false ones are left out" <|
            \_ ->
                Html.div [] [ Html.button [ Attr.disabled True ] [], Html.button [ Attr.disabled False ] [] ]
                    |> Element.toString
                    |> Expect.equal "<div><button disabled=\"\"></button><button></button></div>"
        , test "class and style accumulate" <|
            \_ ->
                Html.div [ Attr.class "a", Attr.class "b", Attr.style "color" "red", Attr.style "top" "0" ] []
                    |> Element.toString
                    |> Expect.equal "<div class=\"a b\" style=\"color: red; top: 0\"></div>"
        , test "handlers and properties are left out" <|
            \_ ->
                Html.button [ Events.onClick (), Attr.property "config" (Encode.int 1) ] [ Element.text "go" ]
                    |> Element.toString
                    |> Expect.equal "<button>go</button>"
        , test "default values are reflected into attributes" <|
            \_ ->
                Html.div []
                    [ Html.input [ Attr.defaultValue "x", Attr.defaultChecked True ]
                    , Html.input [ Attr.defaultChecked False ]
                    , Html.option [ Attr.defaultSelected True ] []
                    ]
                    |> Element.toString
                    |> Expect.equal "<div><input checked=\"\" value=\"x\"><input><option selected=\"\"></option></div>"
        , test "an attribute wins over the default it reflects" <|
            \_ ->
                Html.input [ Attr.value "a", Attr.defaultValue "b" ]
                    |> Element.toString
                    |> Expect.equal "<input value=\"a\">"
        ]


structure : Test
structure =
    describe "fragments and keys"
        [ test "fragments are spliced into their parent" <|
            \_ ->
                Html.ul [] [ Element.fragment [ Html.li [] [], Element.none, Element.fragment [ Html.li [] [] ] ] ]
                    |> Element.toString
                    |> Expect.equal "<ul><li></li><li></li></ul>"
        , test "a fragment as the whole view renders the way it mounts" <|
            \_ ->
                [ Element.none, Element.fragment [ Html.b [] [] ], Element.fragment [ Html.b [] [], Html.i [] [] ] ]
                    |> List.map Element.toString
                    |> Expect.equal [ "", "<b></b>", "<jorn-fragment style=\"display: contents\"><b></b><i></i></jorn-fragment>" ]
        , test "keyed children render in order" <|
            \_ ->
                Keyed.ul [] [ ( "b", Html.li [] [ Element.text "B" ] ), ( "a", Html.li [] [ Element.text "A" ] ) ]
                    |> Element.toString
                    |> Expect.equal "<ul><li>B</li><li>A</li></ul>"
        ]


readable : Test
readable =
    describe "toReadableString"
        [ test "indents children, and keeps short elements on one line" <|
            \_ ->
                Html.div [ Attr.class "card" ]
                    [ Html.h1 [] [ Element.text "Title" ]
                    , Html.br []
                    , Html.p [] [ Element.text "One ", Html.b [] [ Element.text "two" ] ]
                    , Html.span [] []
                    , Element.unsafeRawHtml "" "section" [] "<i>raw</i>"
                    ]
                    |> Element.toReadableString
                    |> Expect.equal
                        (String.join "\n"
                            [ "<div class=\"card\">"
                            , "  <h1>Title</h1>"
                            , "  <br>"
                            , "  <p>"
                            , "    One "
                            , "    <b>two</b>"
                            , "  </p>"
                            , "  <span></span>"
                            , "  <section>"
                            , "    <i>raw</i>"
                            , "  </section>"
                            , "</div>"
                            ]
                        )
        ]
