module ElementTest exposing (suite)

import Expect
import Jorn.Element as Element
import Jorn.Element.Html as Html
import Jorn.Internal.Vdom as Vdom
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Jorn.Element.Html"
        [ test "an element helper uses its tag name" <|
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
