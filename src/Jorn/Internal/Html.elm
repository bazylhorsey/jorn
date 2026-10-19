module Jorn.Internal.Html exposing (toDocumentString, toReadableString, toString)

{-| Rendering a view as HTML: what the browser's `innerHTML` gives for the
page after mounting it, without the handlers.

Properties don't appear, since HTML can't express them, except the three the
browser reflects into attributes: `defaultValue`, `defaultChecked` and
`defaultSelected` become `value`, `checked` and `selected` when no attribute of
that name is set. A `textarea`'s `value` becomes its content, which is where
HTML keeps it.

The string is built as a list of pieces and joined once at the end, so
rendering stays linear in the size of the view.

-}

import Dict exposing (Dict)
import Jorn.Internal.Vdom as Vdom exposing (Closing(..), Element(..))
import Json.Decode as Decode


toString : Element msg -> String
toString element =
    String.concat (List.reverse (render Escaped (Vdom.root element) []))


toDocumentString : Element msg -> String
toDocumentString element =
    "<!doctype html>" ++ toString element


toReadableString : Element msg -> String
toReadableString element =
    String.join "\n" (List.reverse (readable "" Escaped (Vdom.root element) []))



-- SHAPES


{-| How text is written. Inside an HTML `script` or `style`, the browser reads
text as it is, so it isn't escaped.
-}
type TextMode
    = Escaped
    | RawText


type Shape msg
    = Skip
    | Leaf String
    | Many (List (Element msg))
    | Branch
        { open : String
        , close : String
        , content : Content msg
        }


type Content msg
    = Children TextMode (List (Element msg))
    | Html String


shape : TextMode -> Element msg -> Shape msg
shape mode element =
    case element of
        Text content ->
            case mode of
                Escaped ->
                    Leaf (escapeText content)

                RawText ->
                    Leaf (String.replace "</" "<\\/" content)

        Fragment children ->
            Many (Vdom.flatten children)

        Keyed _ wrapped ->
            shape mode wrapped

        Element namespace tag closing attributes children ->
            if validTag tag then
                let
                    attrs =
                        reflected (Vdom.facts attributes)

                    ( finalAttrs, kids ) =
                        if namespace == "" && tag == "textarea" then
                            case Dict.get "value" attrs of
                                Just value ->
                                    ( Dict.remove "value" attrs, [ Text value ] )

                                Nothing ->
                                    ( attrs, Vdom.flatten children )

                        else
                            ( attrs, Vdom.flatten children )

                    start =
                        "<" ++ tag ++ attributesToString finalAttrs
                in
                case ( closing, kids ) of
                    ( Void, _ ) ->
                        Branch { open = start ++ ">", close = "", content = Children Escaped [] }

                    ( SelfClosing, [] ) ->
                        Branch { open = start ++ " />", close = "", content = Children Escaped [] }

                    _ ->
                        Branch
                            { open = start ++ ">"
                            , close = "</" ++ tag ++ ">"
                            , content = Children (textMode namespace tag) kids
                            }

            else
                Skip

        Raw _ tag attributes html ->
            if validTag tag then
                Branch
                    { open = "<" ++ tag ++ attributesToString (reflected (Vdom.facts attributes)) ++ ">"
                    , close = "</" ++ tag ++ ">"
                    , content = Html html
                    }

            else
                Skip


textMode : String -> String -> TextMode
textMode namespace tag =
    if namespace == "" && (tag == "script" || tag == "style") then
        RawText

    else
        Escaped



-- RENDERING


render : TextMode -> Element msg -> List String -> List String
render mode element acc =
    case shape mode element of
        Skip ->
            acc

        Leaf string ->
            string :: acc

        Many children ->
            List.foldl (render mode) acc children

        Branch b ->
            case b.content of
                Children childMode children ->
                    b.close :: List.foldl (render childMode) (b.open :: acc) children

                Html html ->
                    b.close :: html :: b.open :: acc


{-| One node per line, children indented under their parent. An element with
nothing in it, or only a line of text, stays on one line.
-}
readable : String -> TextMode -> Element msg -> List String -> List String
readable indent mode element lines =
    case shape mode element of
        Skip ->
            lines

        Leaf string ->
            (indent ++ string) :: lines

        Many children ->
            List.foldl (readable indent mode) lines children

        Branch b ->
            case b.content of
                Html "" ->
                    (indent ++ b.open ++ b.close) :: lines

                Html html ->
                    (indent ++ b.close) :: (indent ++ "  " ++ html) :: (indent ++ b.open) :: lines

                Children childMode children ->
                    case List.map Vdom.unkey children of
                        [] ->
                            (indent ++ b.open ++ b.close) :: lines

                        [ Text content ] ->
                            if String.contains "\n" content then
                                multiline indent b.open b.close childMode children lines

                            else
                                case shape childMode (Text content) of
                                    Leaf string ->
                                        (indent ++ b.open ++ string ++ b.close) :: lines

                                    _ ->
                                        multiline indent b.open b.close childMode children lines

                        _ ->
                            multiline indent b.open b.close childMode children lines


multiline : String -> String -> String -> TextMode -> List (Element msg) -> List String -> List String
multiline indent open close mode children lines =
    (indent ++ close) :: List.foldl (readable (indent ++ "  ") mode) ((indent ++ open) :: lines) children



-- ATTRIBUTES


attributesToString : Dict String String -> String
attributesToString attrs =
    Dict.foldr
        (\name value acc ->
            if validAttributeName name then
                " " ++ name ++ "=\"" ++ escapeAttribute value ++ "\"" ++ acc

            else
                acc
        )
        ""
        attrs


reflected : Vdom.Facts msg -> Dict String String
reflected facts =
    facts.attrs
        |> reflect "value" (decodeProperty Decode.string "defaultValue" facts)
        |> reflect "checked" (flag "defaultChecked" facts)
        |> reflect "selected" (flag "defaultSelected" facts)


reflect : String -> Maybe String -> Dict String String -> Dict String String
reflect name value attrs =
    case value of
        Just v ->
            if Dict.member name attrs then
                attrs

            else
                Dict.insert name v attrs

        Nothing ->
            attrs


flag : String -> Vdom.Facts msg -> Maybe String
flag name facts =
    case decodeProperty Decode.bool name facts of
        Just True ->
            Just ""

        _ ->
            Nothing


decodeProperty : Decode.Decoder a -> String -> Vdom.Facts msg -> Maybe a
decodeProperty decoder name facts =
    Dict.get name facts.props
        |> Maybe.andThen (Decode.decodeValue decoder >> Result.toMaybe)



-- ESCAPING


escapeText : String -> String
escapeText string =
    if String.any (\c -> c == '&' || c == '<' || c == '>' || c == '\u{00A0}') string then
        string
            |> String.replace "&" "&amp;"
            |> String.replace "<" "&lt;"
            |> String.replace ">" "&gt;"
            |> String.replace "\u{00A0}" "&nbsp;"

    else
        string


escapeAttribute : String -> String
escapeAttribute string =
    if String.any (\c -> c == '&' || c == '"' || c == '<' || c == '>' || c == '\u{00A0}') string then
        string
            |> String.replace "&" "&amp;"
            |> String.replace "\"" "&quot;"
            |> String.replace "<" "&lt;"
            |> String.replace ">" "&gt;"
            |> String.replace "\u{00A0}" "&nbsp;"

    else
        string


{-| Names the browser would refuse are left out rather than written, so a
name can never break out of its tag.
-}
validTag : String -> Bool
validTag tag =
    case String.uncons tag of
        Just ( first, _ ) ->
            Char.isAlpha first && not (String.any forbidden tag)

        Nothing ->
            False


validAttributeName : String -> Bool
validAttributeName name =
    not (String.isEmpty name) && not (String.any forbidden name)


forbidden : Char -> Bool
forbidden c =
    let
        code =
            Char.toCode c
    in
    code < 0x21 || code == 0x7F || c == '"' || c == '\'' || c == '<' || c == '>' || c == '/' || c == '='
