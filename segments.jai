// Load each text file as an array of string as elements into each thing
#import "File";

SEGMENT_SIZE :: 20;

EMPTY_LEVELS :: false;

#if EMPTY_LEVELS {
TOP_LEFT_COUNT :: 1;
TOP_RIGHT_COUNT :: 1;
BOTTOM_LEFT_COUNT :: 1;
BOTTOM_RIGHT_COUNT :: 1;
LEVEL_FOLDER :: "empty_levels";
}
else 
{
TOP_LEFT_COUNT :: 2;
TOP_RIGHT_COUNT :: 2;
BOTTOM_LEFT_COUNT :: 2;
BOTTOM_RIGHT_COUNT :: 2;
LEVEL_FOLDER :: "levels";
}

TOP_LEFT :: #run -> []string {
  loaded_strings: [TOP_LEFT_COUNT]string;
  for 1..TOP_LEFT_COUNT {
    filename := tprint("%/top_left/%", LEVEL_FOLDER, it);
    content, success := read_entire_file(filename, true);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("top_left count = %\n", TOP_LEFT_COUNT);
  return loaded_strings;
}


BOTTOM_LEFT :: #run -> []string {
  loaded_strings: [BOTTOM_LEFT_COUNT]string;
  for 1..BOTTOM_LEFT_COUNT {
    filename := tprint("%/bottom_left/%", LEVEL_FOLDER, it);
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
    filename := tprint("%/bottom_right/%", LEVEL_FOLDER, it);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("bottom_right count = %\n", BOTTOM_RIGHT_COUNT);
  return loaded_strings;
};


TOP_RIGHT :: #run -> []string {
  loaded_strings: [TOP_RIGHT_COUNT]string;
  for 1..TOP_RIGHT_COUNT {
    filename := tprint("%/top_right/%", LEVEL_FOLDER, it);
    content, success := read_entire_file(filename);
    assert(success);
    loaded_strings[it-1] = content;
  }
  print("top_right count = %\n", TOP_RIGHT_COUNT);
  return loaded_strings;
};

