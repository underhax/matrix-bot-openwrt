if [ -n "$RAW_TARGET_ROOM" ]; then
    ROOMS_TO_TRY="$RAW_TARGET_ROOM"
else
    ROOMS_TO_TRY="$MATRIX_ROOM_IDS"
fi

if [ -z "$ROOMS_TO_TRY" ]; then
    printf '[Error] No room ID specified and MATRIX_ROOM_IDS is empty in config\n' >&2
    exit 1
fi

for CURRENT_ROOM in $ROOMS_TO_TRY; do
    TARGET_ROOM=$(printf '%s' "$CURRENT_ROOM" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!#=-')
    [ -z "$TARGET_ROOM" ] && continue

    ROOM_ID_ESC=$(printf '%s' "$TARGET_ROOM" | sed 's/#/%23/g; s/!/%21/g')
