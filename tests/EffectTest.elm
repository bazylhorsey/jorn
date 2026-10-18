module EffectTest exposing (suite)

import Expect
import Jorn.Effect as Effect
import Jorn.Internal.Effect as Internal exposing (Item(..))
import Json.Encode as Encode
import Test exposing (Test, describe, test)


{-| Commands can't be inspected, so describe each item by what can be seen.
-}
describeItems : Internal.Effect msg -> List String
describeItems (Internal.Effect items) =
    List.map
        (\item ->
            case item of
                Command _ ->
                    "command"

                Client instruction ->
                    Encode.encode 0 instruction

                BeforePaint msg ->
                    "before " ++ Debug.toString msg

                AfterPaint msg ->
                    "after " ++ Debug.toString msg
        )
        items


suite : Test
suite =
    describe "Jorn.Effect"
        [ test "none is empty and batch keeps order" <|
            \_ ->
                Effect.batch [ Effect.none, Effect.afterPaint 1, Effect.batch [ Effect.beforePaint 2, Effect.fromCmd Cmd.none ] ]
                    |> describeItems
                    |> Expect.equal [ "after 1", "before 2", "command" ]
        , test "map reaches paint messages" <|
            \_ ->
                Effect.batch [ Effect.beforePaint 1, Effect.afterPaint 2, Effect.focus "x" ]
                    |> Effect.map ((*) 10)
                    |> describeItems
                    |> Expect.equal [ "before 10", "after 20", """{"effect":"focus","id":"x"}""" ]
        , test "golden patcher instructions" <|
            \_ ->
                Effect.batch
                    [ Effect.focus "a"
                    , Effect.blur "b"
                    , Effect.scrollIntoView "c"
                    , Effect.event "saved" (Encode.int 1)
                    , Effect.client "copy" (Encode.string "x")
                    ]
                    |> describeItems
                    |> Expect.equal
                        [ """{"effect":"focus","id":"a"}"""
                        , """{"effect":"blur","id":"b"}"""
                        , """{"effect":"scroll-into-view","id":"c"}"""
                        , """{"effect":"event","name":"saved","detail":1}"""
                        , """{"effect":"client","name":"copy","payload":"x"}"""
                        ]
        ]
