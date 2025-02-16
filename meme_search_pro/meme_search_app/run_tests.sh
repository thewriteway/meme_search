#!/bin/bash

# Prepare the database
bin/rails db:test:prepare

# Loop through each test file in the system test directory and run it
for test_file in test/system/*_test.rb; do
  echo "Running $test_file..."
  bin/rails test "$test_file"
done