"""Reference model for the four-element unsigned dot-product accelerator."""

ELEM_WIDTH = 8
NUM_ELEMS = 4
ELEM_MASK = (1 << ELEM_WIDTH) - 1
VECTOR_MASK = (1 << (ELEM_WIDTH * NUM_ELEMS)) - 1


def unpack_u8_vector(vec: int) -> list[int]:
    """Return four unsigned bytes in the accelerator's little-lane order."""
    if not 0 <= vec <= VECTOR_MASK:
        raise ValueError(f"packed vector must be a 32-bit unsigned value: {vec}")

    return [(vec >> (ELEM_WIDTH * i)) & ELEM_MASK for i in range(NUM_ELEMS)]


def dot_product(vec_a: int, vec_b: int) -> int:
    """Compute sum(a[i] * b[i]) for two packed four-byte vectors."""
    a = unpack_u8_vector(vec_a)
    b = unpack_u8_vector(vec_b)
    return sum(a_elem * b_elem for a_elem, b_elem in zip(a, b))


def run_self_test() -> None:
    """Check fixed vectors with independently specified expected results."""
    test_cases = [
        (0x0000000C, 0x00000007, 84),
        (0x04030201, 0x08070605, 70),
        (0x00000000, 0x06070809, 0),
        (0xFFFFFFFF, 0xFFFFFFFF, 260_100),
        (0x00000001, 0x06070809, 9),
        (0x01000000, 0x06070809, 6),
    ]

    for vec_a, vec_b, expected in test_cases:
        actual = dot_product(vec_a, vec_b)
        assert actual == expected, (
            f"A=0x{vec_a:08X}, B=0x{vec_b:08X}: "
            f"expected {expected}, got {actual}"
        )
        print(
            f"[PASS] A=0x{vec_a:08X}, B=0x{vec_b:08X}, result={actual}"
        )

    print(f"PYTHON GOLDEN MODEL PASSED: {len(test_cases)} tests")


if __name__ == "__main__":
    run_self_test()
