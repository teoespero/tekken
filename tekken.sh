#!/usr/bin/env bash

# Bash Fighter: Iron Terminal
# A small Tekken-style, one-player ASCII fighting game.
# Requires Bash 4+ and a terminal with tput.

FPS=20
FRAME_DELAY="0.05"
ROUND_SECONDS=60
ROUNDS_TO_WIN=2

PLAYER_NAME="TEO"
CPU_NAME="CPU"

cleanup() {
    printf '\033[0m\033[?25h\033[?1049l'
    stty sane 2>/dev/null || true
}
trap cleanup EXIT INT TERM

repeat_char() {
    local char="$1" count="$2" out=""
    printf -v out '%*s' "$count" ''
    printf '%s' "${out// /$char}"
}

health_bar() {
    local hp="$1" width=16 filled empty
    (( hp < 0 )) && hp=0
    (( hp > 100 )) && hp=100
    filled=$((hp * width / 100))
    empty=$((width - filled))
    printf '[%s%s]' "$(repeat_char '#' "$filled")" "$(repeat_char '-' "$empty")"
}

put() {
    # put ROW COLUMN TEXT
    tput cup "$1" "$2"
    printf '%s' "$3"
}

sprite_player() {
    local action="$1"
    case "$action" in
        punch)
            SPRITE=("  O__" " /|  " "  |  " " / \\" )
            ;;
        kick)
            SPRITE=("  O  " " /|\\ " "  |__" " /   ")
            ;;
        block)
            SPRITE=(" \\O/ " "  |  " "  |  " " / \\" )
            ;;
        hurt)
            SPRITE=(" \\O  " "  |\\ " "  |  " " / \\" )
            ;;
        *)
            SPRITE=("  O  " " /|\\ " "  |  " " / \\" )
            ;;
    esac
}

sprite_cpu() {
    local action="$1"
    case "$action" in
        punch)
            SPRITE=("__O  " "  |\\ " "  |  " " / \\" )
            ;;
        kick)
            SPRITE=("  O  " " /|\\ " "__|  " "   \\ ")
            ;;
        block)
            SPRITE=(" \\O/ " "  |  " "  |  " " / \\" )
            ;;
        hurt)
            SPRITE=("  O/ " " /|  " "  |  " " / \\" )
            ;;
        *)
            SPRITE=("  O  " " /|\\ " "  |  " " / \\" )
            ;;
    esac
}

draw_sprite() {
    local top="$1" left="$2" side="$3" action="$4" row

    if [[ "$side" == "player" ]]; then
        sprite_player "$action"
    else
        sprite_cpu "$action"
    fi

    for row in "${!SPRITE[@]}"; do
        put $((top + row)) "$left" "${SPRITE[$row]}"
    done
}

center_text() {
    local text="$1" width="$2"
    local pad=$(((width - ${#text}) / 2))
    (( pad < 0 )) && pad=0
    printf '%*s%s' "$pad" '' "$text"
}

show_message() {
    local text="$1" row="$2"
    put "$row" 0 "$(repeat_char ' ' "$SCREEN_WIDTH")"
    put "$row" 0 "$(center_text "$text" "$SCREEN_WIDTH")"
}

reset_round() {
    PLAYER_HP=100
    CPU_HP=100
    PLAYER_X=7
    CPU_X=$((SCREEN_WIDTH - 12))

    PLAYER_ACTION="idle"
    CPU_ACTION="idle"
    PLAYER_ACTION_TICKS=0
    CPU_ACTION_TICKS=0
    PLAYER_HIT_DONE=0
    CPU_HIT_DONE=0
    PLAYER_BLOCK_TICKS=0
    CPU_BLOCK_TICKS=0
    PLAYER_HURT_TICKS=0
    CPU_HURT_TICKS=0
    PLAYER_JUMP_INDEX=0
    CPU_THINK_TICKS=0
    TICK=0
    MESSAGE="FIGHT!"
    MESSAGE_TICKS=24
}

attack_player() {
    local kind="$1"
    [[ "$PLAYER_ACTION" != "idle" ]] && return
    (( PLAYER_HURT_TICKS > 0 )) && return

    PLAYER_ACTION="$kind"
    PLAYER_HIT_DONE=0
    if [[ "$kind" == "punch" ]]; then
        PLAYER_ACTION_TICKS=7
    else
        PLAYER_ACTION_TICKS=10
    fi
}

attack_cpu() {
    local kind="$1"
    [[ "$CPU_ACTION" != "idle" ]] && return
    (( CPU_HURT_TICKS > 0 )) && return

    CPU_ACTION="$kind"
    CPU_HIT_DONE=0
    if [[ "$kind" == "punch" ]]; then
        CPU_ACTION_TICKS=7
    else
        CPU_ACTION_TICKS=10
    fi
}

apply_player_hit() {
    local range damage blocked=0 distance=$((CPU_X - PLAYER_X))

    if [[ "$PLAYER_ACTION" == "punch" ]]; then
        range=8
        damage=$((RANDOM % 5 + 6))
    else
        range=10
        damage=$((RANDOM % 6 + 10))
    fi

    (( distance > range )) && return

    if (( CPU_BLOCK_TICKS > 0 )); then
        damage=$(((damage + 2) / 3))
        blocked=1
    fi

    CPU_HP=$((CPU_HP - damage))
    (( CPU_HP < 0 )) && CPU_HP=0

    if (( blocked == 1 )); then
        MESSAGE="CPU BLOCKED: -$damage"
        MESSAGE_TICKS=10
    else
        CPU_HURT_TICKS=5
        CPU_X=$((CPU_X + 2))
        (( CPU_X > SCREEN_WIDTH - 8 )) && CPU_X=$((SCREEN_WIDTH - 8))
        MESSAGE="HIT! -$damage"
        MESSAGE_TICKS=10
    fi
}

apply_cpu_hit() {
    local range damage blocked=0 distance=$((CPU_X - PLAYER_X))

    if [[ "$CPU_ACTION" == "punch" ]]; then
        range=8
        damage=$((RANDOM % 5 + 5))
    else
        range=10
        damage=$((RANDOM % 6 + 9))
    fi

    (( distance > range )) && return

    if (( PLAYER_BLOCK_TICKS > 0 )); then
        damage=$(((damage + 2) / 3))
        blocked=1
    fi

    PLAYER_HP=$((PLAYER_HP - damage))
    (( PLAYER_HP < 0 )) && PLAYER_HP=0

    if (( blocked == 1 )); then
        MESSAGE="BLOCKED: -$damage"
        MESSAGE_TICKS=10
    else
        PLAYER_HURT_TICKS=5
        PLAYER_X=$((PLAYER_X - 2))
        (( PLAYER_X < 2 )) && PLAYER_X=2
        MESSAGE="OUCH! -$damage"
        MESSAGE_TICKS=10
    fi
}

process_actions() {
    if (( PLAYER_ACTION_TICKS > 0 )); then
        if [[ "$PLAYER_ACTION" == "punch" && $PLAYER_ACTION_TICKS -eq 4 && $PLAYER_HIT_DONE -eq 0 ]]; then
            apply_player_hit
            PLAYER_HIT_DONE=1
        elif [[ "$PLAYER_ACTION" == "kick" && $PLAYER_ACTION_TICKS -eq 6 && $PLAYER_HIT_DONE -eq 0 ]]; then
            apply_player_hit
            PLAYER_HIT_DONE=1
        fi
        ((PLAYER_ACTION_TICKS--))
        if (( PLAYER_ACTION_TICKS == 0 )); then
            PLAYER_ACTION="idle"
        fi
    fi

    if (( CPU_ACTION_TICKS > 0 )); then
        if [[ "$CPU_ACTION" == "punch" && $CPU_ACTION_TICKS -eq 4 && $CPU_HIT_DONE -eq 0 ]]; then
            apply_cpu_hit
            CPU_HIT_DONE=1
        elif [[ "$CPU_ACTION" == "kick" && $CPU_ACTION_TICKS -eq 6 && $CPU_HIT_DONE -eq 0 ]]; then
            apply_cpu_hit
            CPU_HIT_DONE=1
        fi
        ((CPU_ACTION_TICKS--))
        if (( CPU_ACTION_TICKS == 0 )); then
            CPU_ACTION="idle"
        fi
    fi

    (( PLAYER_BLOCK_TICKS > 0 )) && ((PLAYER_BLOCK_TICKS--))
    (( CPU_BLOCK_TICKS > 0 )) && ((CPU_BLOCK_TICKS--))
    (( PLAYER_HURT_TICKS > 0 )) && ((PLAYER_HURT_TICKS--))
    (( CPU_HURT_TICKS > 0 )) && ((CPU_HURT_TICKS--))
    (( MESSAGE_TICKS > 0 )) && ((MESSAGE_TICKS--))

    if (( PLAYER_JUMP_INDEX > 0 )); then
        ((PLAYER_JUMP_INDEX++))
        (( PLAYER_JUMP_INDEX >= ${#JUMP_OFFSETS[@]} )) && PLAYER_JUMP_INDEX=0
    fi
}

cpu_ai() {
    local distance=$((CPU_X - PLAYER_X))

    ((CPU_THINK_TICKS--))
    (( CPU_THINK_TICKS > 0 )) && return
    CPU_THINK_TICKS=$((RANDOM % 4 + 2))

    if [[ "$PLAYER_ACTION" != "idle" && $distance -le 10 && $((RANDOM % 100)) -lt 45 ]]; then
        CPU_BLOCK_TICKS=6
        return
    fi

    [[ "$CPU_ACTION" != "idle" ]] && return
    (( CPU_HURT_TICKS > 0 )) && return

    if (( distance > 10 )); then
        CPU_X=$((CPU_X - 1))
    elif (( distance < 6 )); then
        CPU_X=$((CPU_X + 1))
    else
        local roll=$((RANDOM % 100))
        if (( roll < 50 )); then
            attack_cpu "punch"
        elif (( roll < 80 )); then
            attack_cpu "kick"
        elif (( roll < 85 )); then
            CPU_BLOCK_TICKS=6
        fi
    fi

    (( CPU_X <= PLAYER_X + 5 )) && CPU_X=$((PLAYER_X + 5))
    (( CPU_X > SCREEN_WIDTH - 8 )) && CPU_X=$((SCREEN_WIDTH - 8))
}

handle_input() {
    local key=""
    if IFS= read -rsn1 -t 0.001 key; then
        case "${key,,}" in
            a)
                if [[ "$PLAYER_ACTION" == "idle" && $PLAYER_HURT_TICKS -eq 0 ]]; then
                    PLAYER_X=$((PLAYER_X - 2))
                    (( PLAYER_X < 2 )) && PLAYER_X=2
                fi
                ;;
            d)
                if [[ "$PLAYER_ACTION" == "idle" && $PLAYER_HURT_TICKS -eq 0 ]]; then
                    PLAYER_X=$((PLAYER_X + 2))
                    (( PLAYER_X > CPU_X - 5 )) && PLAYER_X=$((CPU_X - 5))
                fi
                ;;
            w)
                (( PLAYER_JUMP_INDEX == 0 )) && PLAYER_JUMP_INDEX=1
                ;;
            j) attack_player "punch" ;;
            k) attack_player "kick" ;;
            l) PLAYER_BLOCK_TICKS=6 ;;
            q) QUIT_GAME=1 ;;
        esac
    fi
}

draw_frame() {
    local time_left=$((ROUND_SECONDS - TICK / FPS))
    local floor_row=20
    local player_top cpu_top player_visual cpu_visual jump_offset=0
    (( time_left < 0 )) && time_left=0

    printf '\033[H'
    printf '%-*s' "$SCREEN_WIDTH" "BASH FIGHTER: IRON TERMINAL"
    printf '\n'
    printf '%-5s %s  HP:%3d' "$PLAYER_NAME" "$(health_bar "$PLAYER_HP")" "$PLAYER_HP"
    printf '%*s' 5 ''
    printf 'TIME:%02d' "$time_left"
    printf '%*s' 5 ''
    printf 'HP:%3d %s %-5s' "$CPU_HP" "$(health_bar "$CPU_HP")" "$CPU_NAME"
    printf '\n'
    printf 'Score %s:%d  %s:%d | A/D move  W jump  J punch  K kick  L block  Q quit\n' \
        "$PLAYER_NAME" "$PLAYER_WINS" "$CPU_NAME" "$CPU_WINS"

    printf '+%s+\n' "$(repeat_char '-' $((SCREEN_WIDTH - 2)))"
    for ((r=0; r<15; r++)); do
        printf '|%s|\n' "$(repeat_char ' ' $((SCREEN_WIDTH - 2)))"
    done
    printf '+%s+\n' "$(repeat_char '=' $((SCREEN_WIDTH - 2)))"
    if (( MESSAGE_TICKS > 0 )); then
        printf '%-*s\n' "$SCREEN_WIDTH" "$MESSAGE"
    else
        printf '%-*s\n' "$SCREEN_WIDTH" ""
    fi

    player_top=$((floor_row - 4))
    cpu_top=$((floor_row - 4))

    if (( PLAYER_JUMP_INDEX > 0 )); then
        jump_offset=${JUMP_OFFSETS[$PLAYER_JUMP_INDEX]}
        player_top=$((player_top - jump_offset))
    fi

    if (( PLAYER_HURT_TICKS > 0 )); then
        player_visual="hurt"
    elif (( PLAYER_BLOCK_TICKS > 0 )); then
        player_visual="block"
    else
        player_visual="$PLAYER_ACTION"
    fi

    if (( CPU_HURT_TICKS > 0 )); then
        cpu_visual="hurt"
    elif (( CPU_BLOCK_TICKS > 0 )); then
        cpu_visual="block"
    else
        cpu_visual="$CPU_ACTION"
    fi

    draw_sprite "$player_top" "$PLAYER_X" "player" "$player_visual"
    draw_sprite "$cpu_top" "$CPU_X" "cpu" "$cpu_visual"

}

round_result() {
    local time_left=$((ROUND_SECONDS - TICK / FPS))

    if (( PLAYER_HP <= 0 && CPU_HP <= 0 )); then
        RESULT="DOUBLE K.O."
    elif (( CPU_HP <= 0 )); then
        RESULT="$PLAYER_NAME WINS THE ROUND"
        ((PLAYER_WINS++))
    elif (( PLAYER_HP <= 0 )); then
        RESULT="$CPU_NAME WINS THE ROUND"
        ((CPU_WINS++))
    elif (( time_left <= 0 )); then
        if (( PLAYER_HP > CPU_HP )); then
            RESULT="TIME UP - $PLAYER_NAME WINS"
            ((PLAYER_WINS++))
        elif (( CPU_HP > PLAYER_HP )); then
            RESULT="TIME UP - $CPU_NAME WINS"
            ((CPU_WINS++))
        else
            RESULT="TIME UP - DRAW"
        fi
    else
        return 1
    fi

    draw_frame
    show_message "$RESULT" 11
    sleep 1.6
    return 0
}

main() {
    command -v tput >/dev/null 2>&1 || {
        echo "This game requires the 'tput' command."
        exit 1
    }

    [[ -t 0 && -t 1 ]] || {
        echo "Run this game directly inside a terminal."
        exit 1
    }

    SCREEN_WIDTH=$(tput cols)
    (( SCREEN_WIDTH > 100 )) && SCREEN_WIDTH=100
    if (( SCREEN_WIDTH < 78 )); then
        echo "Please enlarge the terminal to at least 78 columns."
        exit 1
    fi

    JUMP_OFFSETS=(0 1 2 3 4 5 4 3 2 1 0)
    PLAYER_WINS=0
    CPU_WINS=0
    QUIT_GAME=0

    printf '\033[?1049h\033[2J\033[H\033[?25l'

    put 4 0 "$(center_text 'BASH FIGHTER: IRON TERMINAL' "$SCREEN_WIDTH")"
    put 7 0 "$(center_text 'A tiny Tekken-style terminal fighting game' "$SCREEN_WIDTH")"
    put 10 0 "$(center_text 'A/D Move | W Jump | J Punch | K Kick | L Block | Q Quit' "$SCREEN_WIDTH")"
    put 13 0 "$(center_text 'Press any key to fight' "$SCREEN_WIDTH")"
    IFS= read -rsn1

    while (( PLAYER_WINS < ROUNDS_TO_WIN && CPU_WINS < ROUNDS_TO_WIN && QUIT_GAME == 0 )); do
        reset_round

        while (( QUIT_GAME == 0 )); do
            handle_input
            cpu_ai
            process_actions
            draw_frame

            if round_result; then
                break
            fi

            ((TICK++))
            sleep "$FRAME_DELAY"
        done
    done

    printf '\033[2J\033[H'
    if (( QUIT_GAME == 1 )); then
        show_message "GAME ENDED" 9
    elif (( PLAYER_WINS > CPU_WINS )); then
        show_message "$PLAYER_NAME IS THE IRON TERMINAL CHAMPION!" 9
    else
        show_message "$CPU_NAME WINS THE MATCH" 9
    fi
    show_message "Final score: $PLAYER_WINS - $CPU_WINS" 11
    show_message "Press any key to exit" 14
    IFS= read -rsn1
}

main "$@"