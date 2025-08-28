#!/bin/bash

echo "Comparing ground truth outputs to new processor"


pass=true

for source_file in programs/*.{s,c}; do
    
    #source_file="programs/copy.s"
    if [ "$source_file" = "programs/crt.s" ]
    then
        continue
    fi

    # Extract the program name
    program=$(echo "$source_file" | cut -d '.' -f1 | cut -d '/' -f2)
    echo "Running $program"

    # Compile and simulate
    # make $program.out
    make $program.syn.out

    # Compare *.wb file
    echo "Compare writeback output for $program"
    # if diff -q output/$program.wb golden/$program.wb &>/dev/null; then
    if diff -q output/$program.syn.wb golden/$program.wb &>/dev/null; then
        echo "in writeback"
        # diff -q output/$program.wb ground_truth/$program.wb
        continue
    else
        echo "Failed in $program.wb"
        echo $?
        pass=false
        break
    fi

    # Compare *.out file
    echo "Compare memory output for $program"
    # if diff -q <(grep '@@@' output/$program.out) <(grep '@@@' golden/$program.out) &>/dev/null; then
    if diff -q <(grep '@@@' output/$program.syn.out) <(grep '@@@' golden/$program.out) &>/dev/null; then
        continue
    else
        echo "Failed in $program.out"
        echo $?
        pass=false
        break
    fi
done

if [ "$pass" == true ]; then
    echo "Passed"
else
    echo "Fail!!"
fi