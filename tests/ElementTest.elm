module ElementTest exposing (suite)

import Expect
import Jorn.Element as Element
import Jorn.Element.Html as Html
import Jorn.Element.MathMl as MathMl
import Jorn.Element.Svg as Svg
import Jorn.Internal.Vdom as Vdom
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "element helpers"
        [ test "SVG elements are in the SVG namespace" <|
            \_ ->
                [ Svg.svg [] [], Svg.circle [] [], Svg.feGaussianBlur [] [], Svg.text [] [] ]
                    |> List.map shape
                    |> Expect.equal
                        (List.map (\tag -> Just ( Svg.namespace, tag, Vdom.Normal )) [ "svg", "circle", "feGaussianBlur", "text" ])
        , test "SVG names that aren't valid Elm map to their real tags" <|
            \_ ->
                [ Svg.use_ [] [], Svg.missingGlyph [] [] ]
                    |> List.map shape
                    |> Expect.equal [ Just ( Svg.namespace, "use", Vdom.Normal ), Just ( Svg.namespace, "missing-glyph", Vdom.Normal ) ]
        , test "Html.svg and Svg.svg agree" <|
            \_ ->
                shape (Html.svg [] []) |> Expect.equal (shape (Svg.svg [] []))
        , test "MathML elements are in the MathML namespace" <|
            \_ ->
                [ MathMl.math [] [], MathMl.mi [] [], MathMl.mfrac [] [], MathMl.mmultiscripts [] [], MathMl.mprescripts [] [] ]
                    |> List.map shape
                    |> Expect.equal
                        (List.map (\tag -> Just ( MathMl.namespace, tag, Vdom.Normal )) [ "math", "mi", "mfrac", "mmultiscripts", "mprescripts" ])
        , test "annotationXml is <annotation-xml>" <|
            \_ ->
                shape (MathMl.annotationXml [] [])
                    |> Expect.equal (Just ( MathMl.namespace, "annotation-xml", Vdom.Normal ))
        , test "Html.math and MathMl.math agree" <|
            \_ ->
                shape (Html.math [] []) |> Expect.equal (shape (MathMl.math [] []))
        , test "an element helper uses its tag name" <|
            \_ ->
                Html.blockquote [] []
                    |> shape
                    |> Expect.equal (Just ( "", "blockquote", Vdom.Normal ))
        , test "a trailing underscore isn't part of the tag" <|
            \_ ->
                Html.main_ [] []
                    |> shape
                    |> Expect.equal (Just ( "", "main", Vdom.Normal ))
        , test "void elements are marked void and have no children" <|
            \_ ->
                [ Html.area [], Html.base [], Html.br [], Html.col [], Html.embed [], Html.hr [], Html.img [], Html.input [], Html.link [], Html.meta [], Html.source [], Html.track [], Html.wbr [] ]
                    |> List.map shape
                    |> Expect.equal
                        (List.map (\tag -> Just ( "", tag, Vdom.Void ))
                            [ "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr" ]
                        )
        , test "svg and math start their own namespaces" <|
            \_ ->
                [ Html.svg [] [], Html.math [] [] ]
                    |> List.map shape
                    |> Expect.equal
                        [ Just ( "http://www.w3.org/2000/svg", "svg", Vdom.Normal )
                        , Just ( "http://www.w3.org/1998/Math/MathML", "math", Vdom.Normal )
                        ]
        , test "advanced builds the same element as a helper" <|
            \_ ->
                Element.advanced { namespace = "", tag = "br", closing = Element.Void } [] []
                    |> shape
                    |> Expect.equal (shape (Html.br []))
        ]


shape : Element.Element msg -> Maybe ( String, String, Vdom.Closing )
shape element =
    case element of
        Vdom.Element namespace tag closing _ children ->
            if closing == Vdom.Void && not (List.isEmpty children) then
                Nothing

            else
                Just ( namespace, tag, closing )

        _ ->
            Nothing
