module Jorn.Internal.Vdom exposing
    ( Attribute(..)
    , Closing(..)
    , Element(..)
    , EventOptions
    , Facts
    , Node(..)
    , defaultOptions
    , encodeNode
    , encodeOptions
    , facts
    , flatten
    , keys
    , map
    , mapAttribute
    , root
    , toNode
    , unkey
    )

{-| Internal representation. Not exposed from the package, so constructors
stay private while tests and sibling modules can still see them.

`Element` carries decoders (it is what your program builds and what event routing
walks). `Node` is the msg-free projection of it: pure data, safe to serialize,
and what every patch and mount payload is made of.

-}

import Dict exposing (Dict)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Set exposing (Set)


type Element msg
    = Element String String Closing (List (Attribute msg)) (List (Element msg))
      -- namespace, tag, how it closes, attributes, children
    | Text String
    | Fragment (List (Element msg))
    | Keyed String (Element msg)


{-| How an element's tags are written as HTML. Only rendering to a string
cares: the DOM, the diff and the wire are the same for all three.
-}
type Closing
    = Normal
    | Void
    | SelfClosing


type Attribute msg
    = Attr String String
    | Prop String Value
    | On String (Decoder msg)
    | Options EventOptions (Attribute msg)
    | NoAttribute


{-| Event options are static on purpose. A server component has to tell the
client up front whether to call preventDefault, because the decision can't
wait for a round trip. `include` lists the dotted event fields the client
must serialize and send back (for example `target.value`).

Options wrap the handler they apply to, and options on the same handler merge:
`preventDefault` and `stopPropagation` are true if any of them asked, and
`include` is the union of what they asked for. An option wrapped around
anything that isn't a handler is dropped, leaving the attribute as it was.

-}
type alias EventOptions =
    { preventDefault : Bool
    , stopPropagation : Bool
    , include : List String
    }


defaultOptions : EventOptions
defaultOptions =
    { preventDefault = False, stopPropagation = False, include = [] }



-- NORMALIZATION


{-| An element's attribute list folded into lookup tables. Later entries win,
except `class` and `style`, which accumulate: classes joined by spaces, like
elm/html, and style declarations joined by semicolons.
-}
type alias Facts msg =
    { attrs : Dict String String
    , props : Dict String Value
    , events : Dict String ( EventOptions, Decoder msg )
    }


facts : List (Attribute msg) -> Facts msg
facts attributes =
    List.foldl addFact { attrs = Dict.empty, props = Dict.empty, events = Dict.empty } attributes


addFact : Attribute msg -> Facts msg -> Facts msg
addFact attribute acc =
    let
        ( options, bare ) =
            splitOptions attribute
    in
    case bare of
        Attr "class" value ->
            { acc | attrs = Dict.update "class" (accumulate " " value) acc.attrs }

        Attr "style" value ->
            { acc | attrs = Dict.update "style" (accumulate "; " value) acc.attrs }

        Attr name value ->
            { acc | attrs = Dict.insert name value acc.attrs }

        Prop name value ->
            { acc | props = Dict.insert name value acc.props }

        On name decoder ->
            { acc | events = Dict.insert name ( options, decoder ) acc.events }

        Options _ _ ->
            acc

        NoAttribute ->
            acc


{-| Split an attribute into the options wrapped around it and the attribute
underneath, merging any nesting. Options around anything that isn't a handler
are simply dropped, leaving the attribute itself untouched.
-}
splitOptions : Attribute msg -> ( EventOptions, Attribute msg )
splitOptions attribute =
    case attribute of
        Options added wrapped ->
            let
                ( nested, bare ) =
                    splitOptions wrapped
            in
            ( combineOptions added nested, bare )

        _ ->
            ( defaultOptions, attribute )


combineOptions : EventOptions -> EventOptions -> EventOptions
combineOptions added options =
    { preventDefault = added.preventDefault || options.preventDefault
    , stopPropagation = added.stopPropagation || options.stopPropagation
    , include = addPaths added.include options.include
    }


addPaths : List String -> List String -> List String
addPaths paths existing =
    List.foldl
        (\path acc ->
            if List.member path acc then
                acc

            else
                acc ++ [ path ]
        )
        existing
        paths


accumulate : String -> String -> Maybe String -> Maybe String
accumulate separator value existing =
    case existing of
        Nothing ->
            Just value

        Just previous ->
            if String.isEmpty value then
                Just previous

            else if String.isEmpty previous then
                Just value

            else
                Just (previous ++ separator ++ value)



-- FRAGMENTS AND KEYS


{-| Splice fragments into the surrounding list of children, at any depth.
Fragments never reach the wire: paths, patches and mounts only ever see the
flattened children.

Keys survive flattening, as a `Keyed` wrapped directly around a child that is
neither a fragment nor keyed itself. A key on a fragment applies to each of
its children, and the outermost key wins.

Most lists need none of this, and those come back as they are, without being
rebuilt.

-}
flatten : List (Element msg) -> List (Element msg)
flatten children =
    if List.any needsSplicing children then
        List.foldr (spliceChild Nothing) [] children

    else
        children


spliceChild : Maybe String -> Element msg -> List (Element msg) -> List (Element msg)
spliceChild key child acc =
    case child of
        Fragment grandchildren ->
            List.foldr (spliceChild key) acc grandchildren

        Keyed inner wrapped ->
            spliceChild (Just (Maybe.withDefault inner key)) wrapped acc

        _ ->
            case key of
                Just k ->
                    Keyed k child :: acc

                Nothing ->
                    child :: acc


needsSplicing : Element msg -> Bool
needsSplicing html =
    case html of
        Fragment _ ->
            True

        Keyed _ (Fragment _) ->
            True

        Keyed _ (Keyed _ _) ->
            True

        _ ->
            False


{-| The child under its key, if it has one.
-}
unkey : Element msg -> Element msg
unkey html =
    case html of
        Keyed _ wrapped ->
            unkey wrapped

        _ ->
            html


{-| A unique key for every child of a flattened list. Children without a key
are numbered among themselves, so the third unkeyed child in one render
matches the third in the next. A key that repeats gets its occurrence number,
so duplicates match in order instead of colliding. Generated keys use control
characters, which keeps them apart from anything a view would use.
-}
keys : List (Element msg) -> List ( String, Element msg )
keys children =
    let
        step child acc =
            let
                ( raw, unkeyed ) =
                    case child of
                        Keyed key _ ->
                            ( key, acc.unkeyed )

                        _ ->
                            ( "\u{0000}" ++ String.fromInt acc.unkeyed, acc.unkeyed + 1 )

                ( key_, occurrence ) =
                    unique acc.seen raw (Maybe.withDefault 1 (Dict.get raw acc.occurrences))
            in
            { pairs = ( key_, unkey child ) :: acc.pairs
            , unkeyed = unkeyed
            , seen = Set.insert key_ acc.seen
            , occurrences = Dict.insert raw (occurrence + 1) acc.occurrences
            }
    in
    List.foldl step { pairs = [], unkeyed = 0, seen = Set.empty, occurrences = Dict.empty } children
        |> .pairs
        |> List.reverse


unique : Set String -> String -> Int -> ( String, Int )
unique seen raw occurrence =
    let
        candidate =
            if occurrence == 1 then
                raw

            else
                raw ++ "\u{0001}" ++ String.fromInt occurrence
    in
    if Set.member candidate seen then
        unique seen raw (occurrence + 1)

    else
        ( candidate, occurrence )


{-| The node a view puts on screen. A view's root is a single node on the
wire, so a fragment at the root needs a stand-in: with no children it's an
empty text node, with one it's that child, and with several they're wrapped in
a `jorn-fragment` element styled `display: contents`, which leaves layout as
if the wrapper weren't there. A key at the root means nothing and is dropped.
-}
root : Element msg -> Element msg
root html =
    case html of
        Fragment children ->
            case flatten children of
                [] ->
                    Text ""

                [ only ] ->
                    unkey only

                several ->
                    Element "" "jorn-fragment" Normal [ Attr "style" "display: contents" ] several

        Keyed _ wrapped ->
            root wrapped

        _ ->
            html



-- PROJECTION


type Node
    = NodeElement
        { namespace : String
        , tag : String
        , attrs : Dict String String
        , props : Dict String Value
        , events : Dict String EventOptions
        , children : List Node
        }
    | NodeText String


toNode : Element msg -> Node
toNode html =
    case html of
        Text content ->
            NodeText content

        Fragment _ ->
            toNode (root html)

        Keyed _ wrapped ->
            toNode wrapped

        Element namespace tag _ attributes children ->
            let
                f =
                    facts attributes
            in
            NodeElement
                { namespace = namespace
                , tag = tag
                , attrs = f.attrs
                , props = f.props
                , events = Dict.map (\_ ( options, _ ) -> options) f.events
                , children = List.map toNode (flatten children)
                }


encodeNode : Node -> Value
encodeNode node =
    case node of
        NodeText content ->
            Encode.object [ ( "text", Encode.string content ) ]

        NodeElement r ->
            Encode.object
                [ ( "tag", Encode.string r.tag )
                , ( "namespace", Encode.string r.namespace )
                , ( "attrs", Encode.dict identity Encode.string r.attrs )
                , ( "props", Encode.dict identity identity r.props )
                , ( "events", Encode.dict identity encodeOptions r.events )
                , ( "children", Encode.list encodeNode r.children )
                ]


encodeOptions : EventOptions -> Value
encodeOptions options =
    Encode.object
        [ ( "preventDefault", Encode.bool options.preventDefault )
        , ( "stopPropagation", Encode.bool options.stopPropagation )
        , ( "include", Encode.list Encode.string options.include )
        ]



-- MAPPING


{-| Eager: walks the subtree and wraps every decoder. elm/html makes `map`
lazy with kernel code, which a pure package can't do. Lazy map is on the roadmap.
-}
map : (a -> b) -> Element a -> Element b
map f html =
    case html of
        Text content ->
            Text content

        Element namespace tag closing attributes children ->
            Element namespace tag closing (List.map (mapAttribute f) attributes) (List.map (map f) children)

        Fragment children ->
            Fragment (List.map (map f) children)

        Keyed key wrapped ->
            Keyed key (map f wrapped)


mapAttribute : (a -> b) -> Attribute a -> Attribute b
mapAttribute f attribute =
    case attribute of
        Attr name value ->
            Attr name value

        Prop name value ->
            Prop name value

        On name decoder ->
            On name (Json.Decode.map f decoder)

        Options options wrapped ->
            Options options (mapAttribute f wrapped)

        NoAttribute ->
            NoAttribute
