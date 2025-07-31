
create_level :: () {
  #insert -> string {
    code, success := read_entire_file("level.in");
    assert(success);
    return code;
  }
}
