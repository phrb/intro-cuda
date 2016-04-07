#! /bin/bash

cuda-memcheck $1

cuda-memcheck --leak-check full $1
