#!/bin/bash
echo "Calculate the Average CPI"

result_dir="result"
output_file="$result_dir/CPI_result.txt"

if [[ ! -d "$result_dir" ]]; then
    mkdir -p "$result_dir"
    echo "Created directory: $result_dir"
fi

echo "CPI Values and Average:" > "$output_file"

total_cpi=0
count=0

for source_file in output/*.syn.cpi; do
    cpi=$(grep "CPI" "$source_file" | awk -F '=' '{print $2}' | awk '{print $1}')
    
    if [[ ! -z "$cpi" ]]; then
        # echo "$source_file" >> "$output_file"
        echo "$cpi" >> "$output_file"
        total_cpi=$(echo "$total_cpi + $cpi" | bc)
        count=$((count + 1))
    fi
done

if [[ $count -gt 0 ]]; then
    average_cpi=$(echo "scale=6; $total_cpi / $count" | bc)
    echo "Average CPI: $average_cpi" >> "$output_file"
    echo "Average CPI: $average_cpi"
else
    echo "No CPI values found." >> "$output_file"
    echo "No CPI values found."
fi
