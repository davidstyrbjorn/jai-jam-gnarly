
NUM_LEVELS :: 1;

level_factory :: #type ();
levels := level_factory.[create_level_1];

create_level_1 :: () {
  #insert -> string {
    code, success := read_entire_file("levels.jai.in");
    assert(success);
    return code;
  }
}
