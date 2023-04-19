# change this mapping based on the number of different experiments to run 
# (make sure all rw or randrw experiments are at the end of array)
io_type_map=('write' 'read' 'randwrite' 'randread' 'rw' 'randrw')
# change this mapping based on the number of rw or randrw experiments in the io_type_mapping
# (number of elements in this array should match number of rw and randrw elements in io_type_mapping)
mixed_io_m_arg=('50' '50')

max_initiators=5
num_experiments_per=5
run_time_per_experiment=10
run_command='sudo bash run_multi_initiator.sh -l $num_experiments_per -t $run_time_per_experiment -c $j -p $k -w ${io_type_map[$i]} $m_arg_input'

io_map_offset=0
est_time_complete=0
est_time_complete_sec=0

while getopts i:l:t: flag
do
    case "${flag}" in
        i) max_initiators=${OPTARG};;
        l) num_experiments_per=${OPTARG};;
        t) run_time_per_experiment=${OPTARG};;
    esac
done

init_ct=0
for ((i=1; i<$max_initiators; i++))
do
    init_ct=$(($init_ct+$i))
done 
est_time_complete_sec=$(bc <<< $init_ct*$num_experiments_per*$run_time_per_experiment*${#io_type_map[@]})
est_time_complete=$(bc <<< "scale=0; $est_time_complete_sec/60")
echo "========================================================"
echo "ESTIMATED TIME TO COMPLETION: $est_time_complete minutes"
echo "========================================================"

for ((i=0; i<${#io_type_map[@]}; i++))
do
    if [ "${io_type_map[$i]}" = "rw" ] || [ "${io_type_map[$i]}" = "randrw" ]
    then
        break
    fi 
    io_map_offset=$((io_map_offset+1))
done 

if ((${#mixed_io_m_arg[@]} != $(bc <<< ${#io_type_map[@]}-$io_map_offset) ))
then
    echo "ERROR: [run_exp.sh]: size of array mixed_io_m_arg should match number of rw/randrw in array io_type_map"
    echo "Or, an element besides rw/randrw could have been placed after them in the array whereas they should be before"
    exit 125
fi     

rm -rf exp_all_output.txt
rm -rf exp_log.txt
rm -rf exp_out_tab.txt

for ((i=0; i<${#io_type_map[@]}; i++))
do
    m_arg_input=''
    if [ "${io_type_map[$i]}" = "rw" ] || [ "${io_type_map[$i]}" = "randrw" ]
    then
        m_arg_input="-M ${mixed_io_m_arg[$(bc <<< $i-$io_map_offset)]}"
    fi 
    for ((j=1; j<=$max_initiators; j++))
    do
        for ((k=1; k<$j; k++))
        do
            eval "$run_command"
            # echo "run -l $num_experiments_per -t $run_time_per_experiment -c $j -p $k -w ${io_type_map[$i]} $m_arg_input"
            # est_time_complete_sec=$(bc <<< $est_time_complete_sec-$run_time_per_experiment*$num_experiments_per)
            # echo "REMAINING TIME: $(bc <<< "scale=0; $est_time_complete_sec/60") minutes"
        done
    done
done
