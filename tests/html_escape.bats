#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/../src/common/02_helpers.sh"
}

@test "html_escape: bashism replacement" {
    run html_escape 'A & B < C > D " E '\'' F'
    [ "$status" -eq 0 ]
    [ "$output" = "A &amp; B &lt; C &gt; D &quot; E &#39; F" ]
}
