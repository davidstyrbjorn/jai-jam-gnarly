

// Shuffles the elements of an array in-place.
// This is a generic function (due to '$T') and works on an array of any type.
random_shuffle :: (array: *[..]$T) {
    // If the array has 0 or 1 elements, there's nothing to shuffle.
    if array.count <= 1 then return;

    // Iterate backwards from the last element of the array.
    for i: array.count - 1..1 {
        // Pick a random index 'j' from the remaining unshuffled part of the array (from 0 to i, inclusive).
        j := cast(s64) (random_get() % (cast(u64) i + 1));

        // Swap the element at the current position 'i' with the one at the random position 'j'.
        swap_el(*array[i], *array[j]);
    }
}

swap_el :: (a: *$T, b: *T) {
    temp := <<a; // Dereference 'a' to get its value and store it in a temporary variable.
    <<a = <<b;  // Assign the value of 'b' to 'a'.
    <<b = temp; // Assign the original value of 'a' (stored in temp) to 'b'.
}