// Load each text file as an array of string as elements into each thing
#load "segment-info.jai";
#import "File";

TOP_LEFT :: #run -> []string {
  loaded_strings: [TOP_LEFT_COUNT]string;
  for 1..TOP_LEFT_COUNT {
    filename := tprint("top_left/%", it);
    print("%\n", filename);
    content, success := read_entire_file(filename, true);
    assert(success);
    loaded_strings[it-1] = content;
  }
  return loaded_strings;
}


BOTTOM_LEFT :: #run -> []string {
  loaded_strings: [BOTTOM_LEFT_COUNT]string;
  for 1..BOTTOM_LEFT_COUNT {
    filename := tprint("bottom_left/%", it);
    print("%\n", filename);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  return loaded_strings;
};


BOTTOM_RIGHT :: #run -> []string {
  loaded_strings: [BOTTOM_RIGHT_COUNT]string;
  for 1..BOTTOM_RIGHT_COUNT {
    filename := tprint("bottom_right/%", it);
    print("%\n", filename);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  return loaded_strings;
};


TOP_RIGHT :: #run -> []string {
  loaded_strings: [TOP_RIGHT_COUNT]string;
  for 1..TOP_RIGHT_COUNT {
    filename := tprint("top_right/%", it);
    print("%\n", filename);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  return loaded_strings;
};

