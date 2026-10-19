module Reference exposing (apply, render)

{-| A reference implementation of the client patcher, over `Node`.

This is the executable spec the JS runtime has to match: if `apply (diff a b)`
turns `a` into `b` here, a conforming client does the same to the real DOM.

-}

import Dict
import Jorn.Internal.Patch exposing (Patch(..), Path)
import Jorn.Internal.Vdom as Vdom exposing (Node(..))
import Json.Encode as Encode


{-| Canonical string form of a node, for equality checks.
-}
render : Node -> String
render node =
    Encode.encode 0 (Vdom.encodeNode node)


{-| `Nothing` means a patch was invalid for the tree it was applied to.
-}
apply : List Patch -> Node -> Maybe Node
apply patches root =
    List.foldl (\patch acc -> Maybe.andThen (applyOne patch) acc) (Just root) patches


applyOne : Patch -> Node -> Maybe Node
applyOne patch root =
    case patch of
        Replace path node ->
            at path (\_ -> Just node) root

        SetText path content ->
            at path
                (\n ->
                    case n of
                        NodeText _ ->
                            Just (NodeText content)

                        NodeElement _ ->
                            Nothing
                )
                root

        SetHtml path content ->
            at path
                (\n ->
                    case n of
                        NodeElement r ->
                            if r.html == Nothing then
                                Nothing

                            else
                                Just (NodeElement { r | html = Just content })

                        NodeText _ ->
                            Nothing
                )
                root

        SetAttribute path name value ->
            element path (\r -> { r | attrs = Dict.insert name value r.attrs }) root

        RemoveAttribute path name ->
            element path (\r -> { r | attrs = Dict.remove name r.attrs }) root

        SetProperty path name value ->
            element path (\r -> { r | props = Dict.insert name value r.props }) root

        RemoveProperty path name ->
            element path (\r -> { r | props = Dict.remove name r.props }) root

        SetEvent path name options ->
            element path (\r -> { r | events = Dict.insert name options r.events }) root

        RemoveEvent path name ->
            element path (\r -> { r | events = Dict.remove name r.events }) root

        Append path nodes ->
            parent path (\r -> { r | children = r.children ++ nodes }) root

        Truncate path length ->
            parent path (\r -> { r | children = List.take length r.children }) root

        Insert path index node ->
            parent path (\r -> { r | children = List.take index r.children ++ node :: List.drop index r.children }) root
                |> Maybe.andThen (validIndex index (index <= childCount path root))

        Move path from to ->
            childAt path from root
                |> Maybe.andThen
                    (\moved ->
                        parent path
                            (\r ->
                                let
                                    without =
                                        List.take from r.children ++ List.drop (from + 1) r.children
                                in
                                { r | children = List.take to without ++ moved :: List.drop to without }
                            )
                            root
                    )
                |> Maybe.andThen (validIndex to (to < childCount path root))

        Remove path index ->
            childAt path index root
                |> Maybe.andThen (\_ -> parent path (\r -> { r | children = List.take index r.children ++ List.drop (index + 1) r.children }) root)


{-| An index past the end is invalid, rather than quietly clamped.
-}
validIndex : Int -> Bool -> Node -> Maybe Node
validIndex index ok node =
    if ok && index >= 0 then
        Just node

    else
        Nothing


childCount : Path -> Node -> Int
childCount path root =
    case nodeAt path root of
        Just (NodeElement r) ->
            List.length r.children

        _ ->
            -1


childAt : Path -> Int -> Node -> Maybe Node
childAt path index root =
    if index < 0 then
        Nothing

    else
        case nodeAt path root of
            Just (NodeElement r) ->
                List.head (List.drop index r.children)

            _ ->
                Nothing


type alias ElementRecord =
    { namespace : String, tag : String, attrs : Dict.Dict String String, props : Dict.Dict String Encode.Value, events : Dict.Dict String Vdom.EventOptions, children : List Node, html : Maybe String }


{-| Patches that change an element's children. A raw element has none to
change: its content belongs to the browser.
-}
parent : Path -> (ElementRecord -> ElementRecord) -> Node -> Maybe Node
parent path f root =
    case nodeAt path root of
        Just (NodeElement r) ->
            if r.html == Nothing then
                element path f root

            else
                Nothing

        _ ->
            Nothing


element : Path -> (ElementRecord -> ElementRecord) -> Node -> Maybe Node
element path f root =
    at path
        (\n ->
            case n of
                NodeElement r ->
                    Just (NodeElement (f r))

                NodeText _ ->
                    Nothing
        )
        root


at : Path -> (Node -> Maybe Node) -> Node -> Maybe Node
at path f node =
    case path of
        [] ->
            f node

        index :: rest ->
            case node of
                NodeElement r ->
                    case List.head (List.drop index r.children) of
                        Just child ->
                            at rest f child
                                |> Maybe.map
                                    (\updated ->
                                        NodeElement
                                            { r
                                                | children =
                                                    List.indexedMap
                                                        (\i c ->
                                                            if i == index then
                                                                updated

                                                            else
                                                                c
                                                        )
                                                        r.children
                                            }
                                    )

                        Nothing ->
                            Nothing

                NodeText _ ->
                    Nothing


nodeAt : Path -> Node -> Maybe Node
nodeAt path node =
    case ( path, node ) of
        ( [], _ ) ->
            Just node

        ( index :: rest, NodeElement r ) ->
            if index < 0 then
                Nothing

            else
                List.head (List.drop index r.children) |> Maybe.andThen (nodeAt rest)

        ( _ :: _, NodeText _ ) ->
            Nothing
