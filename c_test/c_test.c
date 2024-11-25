#include "zijson.h"
#include <stdio.h>

int main() {
    char result[100];
    char* j = "{\"foo\": 5, \"bar\": {\"hello\": 2}, \"hello\": 3 , \"text\": \"a_text\"}";
    char* path = "$.hello";
    getJSONPath(j, path, result);
    printf("result: %s\n", result);
}