// Load each text file as an array of string as elements into each thing
#load "segment-info.jai";
#import "File";

TOP_LEFT :: #run -> []string {
  loaded_strings: [TOP_LEFT_COUNT]string;
  for 1..TOP_LEFT_COUNT {
    filename := tprint("top_left/%", it);
    content, success := read_entire_file(filename, true);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("top_left count = %\n", BOTTOM_LEFT_COUNT);
  return loaded_strings;
}


BOTTOM_LEFT :: #run -> []string {
  loaded_strings: [BOTTOM_LEFT_COUNT]string;
  for 1..BOTTOM_LEFT_COUNT {
    filename := tprint("bottom_left/%", it);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("bottom_left count = %\n", BOTTOM_LEFT_COUNT);
  return loaded_strings;
};


BOTTOM_RIGHT :: #run -> []string {
  loaded_strings: [BOTTOM_RIGHT_COUNT]string;
  for 1..BOTTOM_RIGHT_COUNT {
    filename := tprint("bottom_right/%", it);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("bottom_right count = %\n", BOTTOM_LEFT_COUNT);
  return loaded_strings;
};


TOP_RIGHT :: #run -> []string {
  loaded_strings: [TOP_RIGHT_COUNT]string;
  for 1..TOP_RIGHT_COUNT {
    filename := tprint("top_right/%", it);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("top_right count = %\n", BOTTOM_LEFT_COUNT);
  return loaded_strings;
};

