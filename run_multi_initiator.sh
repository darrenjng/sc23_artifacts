qdepth=128
iosize=4096
iotype='write'
runtime=10
# make sure to change traddr to your target address
traddr=10.140.81.142
windowsize=32
num_LS=0
mixed_ratio_read='' # means 50 read, rest goes to write

m_arg_input=''
loop=1
output_to_term=0
num_cores=2
prio_map=()
qdepth_map=()
latency_arg_map=()
error_flag=0
run_command='sudo ./build/examples/perf -p ${prio_map[j-1]} -d $j -c $core_mask -i $windowsize -q ${qdepth_map[j-1]} -o $iosize -w $iotype $m_arg_input -t $runtime -r "trtype:TCP adrfam:IPv4 traddr:$traddr trsvcid:4420 subnqn:nqn.2016-06.io.spdk:cnode1" ${latency_arg_map[j-1]}'

while getopts q:o:w:t:r:b:l:d:c:p:M: flag
do
    case "${flag}" in
        q) qdepth=${OPTARG};;
        o) iosize=${OPTARG};;
        w) iotype=${OPTARG};;
        t) runtime=${OPTARG};;
	    r) traddr=${OPTARG};;
	    b) windowsize=${OPTARG};;
        l) loop=${OPTARG};;
        d) output_to_term=${OPTARG};;
        c) num_cores=${OPTARG};;
        p) num_LS=${OPTARG};;
        M) mixed_ratio_read=${OPTARG};;
    esac
done

rm -rf *exp_output_*

if (($num_LS > $num_cores))
then
    echo "ERROR: num_LS in run_multi_initiator.sh should be <= num cores"
    error_flag=1
    exit 125
fi

if [ "$iotype" = "rw" ] || [ "$iotype" = "randrw" ]
then
    m_arg_input="-M $mixed_ratio_read"
fi 

for ((i=0; i < num_cores; i++))
do
    if ((i < $num_LS))
    then
        prio_map+=('LS')
        qdepth_map+=(1)
        latency_arg_map+=('-L')
    else
        prio_map+=('TC')
        qdepth_map+=(128)
        latency_arg_map+=('')
    fi 
done

for ((i = 1; i <= $loop; i++))
do

    core_mask_arr=(1 2 4 8)
    core_mask=0

    echo "=======================================================================" >> exp_log.txt
    echo -e "[$i] Running Experiment with: \n-q $qdepth \n-o $iosize \n-w $iotype $m_arg_input\n-t $runtime \nwindow size=$windowsize \nnumber cores=$num_cores \npriority map=[${prio_map[@]}]" >> exp_log.txt
    echo "=======================================================================" >> exp_log.txt

    for ((j = 1; j <= $num_cores; j++)) # starts at j = 1 to skip first core, change to 0 to include if desired
    do
        core_mask=$(bc <<< ${core_mask_arr[j % ${#core_mask_arr[@]}]})
        if ((j > $num_cores-1))
        then
            if (($output_to_term == 0))
            then
                eval "$run_command" >> exp_output_$j.txt
            else
                eval "$run_command"
            fi
        else
            if (($output_to_term == 0))
            then
                # error detection test =========
                # if (($j == $num_cores-1)) && (($i == $loop))
                # then
                #     m_arg_input="-M "
                # else
                #     m_arg_input="-M $mixed_ratio_read"
                # fi
                # error detection test =========
                eval "$run_command" >> exp_output_$j.txt &
            else
                eval "$run_command" &
            fi
        fi
        if ((j % ${#core_mask_arr[@]} == ${#core_mask_arr[@]}-1))
        then
            for ((k = 0; k < ${#core_mask_arr[@]}; k++))
            do
                core_mask_arr[k]=$(bc <<< ${core_mask_arr[k]}*10)
            done
        fi
    done
done

# error detection test =========
# rm -rf exp_output_1.txt 
# error detection test =========

# ============================================================
# End run perf commands; Begin output reformatting code
# ============================================================

core=1

aggregate_IOPs=0
aggregate_bandwidth=0
ave_latency=0
ave_tail_lat=(0 0) # hard coded

inc=0
for i in exp_output_*.txt; do

    filename=$i
    echo "FILE LOADED: $i" >> exp_log.txt

    match_string="TCP  (addr:$traddr subnqn:nqn.2016-06.io.spdk:cnode1) NSID 1 from core  $core:"
    match_string_lat=('99.99000%' '99.00000%') # hard coded

    IOPS_arr=()
    MIBS_arr=()
    Average_arr=()
    min_arr=()
    max_arr=()
    tail_lat_99=()
    tail_lat_00=()

    data_aves=(0 0 0 0 0 0 0)

    num_exp=0

    while read line; 
    do
        case "$line" in 
            *$match_string*) 
            echo "$line" >> exp_log.txt

            IFS=' ' read -ra ADDR <<< "$line"
            IOPS_arr+=(${ADDR[8]})
            MIBS_arr+=(${ADDR[9]})
            Average_arr+=(${ADDR[10]})
            min_arr+=(${ADDR[11]})
            max_arr+=(${ADDR[12]})
            num_exp=$((num_exp+1))
            ;;
        esac

        suffix="us"
        case "$line" in
            *${match_string_lat[0]}*)
            echo "$line" >> exp_log.txt

            IFS=' ' read -ra ADDR <<< "$line"
            n=${ADDR[2]%"$suffix"}
            tail_lat_99+=($n)
            ;;
        esac

        case "$line" in
            *${match_string_lat[1]}*)
            echo "$line" >> exp_log.txt

            IFS=' ' read -ra ADDR <<< "$line"
            n=${ADDR[2]%"$suffix"}
            tail_lat_00+=($n)
            ;;
        esac


    done < $filename

    n=0
    for k in "${IOPS_arr[@]}"
    do
        data_aves[0]=$(bc <<< ${data_aves[0]}+$k)
        data_aves[1]=$(bc <<< ${data_aves[1]}+${MIBS_arr[n]})
        data_aves[2]=$(bc <<< ${data_aves[2]}+${Average_arr[n]})
        data_aves[3]=$(bc <<< ${data_aves[3]}+${min_arr[n]})
        data_aves[4]=$(bc <<< ${data_aves[4]}+${max_arr[n]})

        if [[ "${prio_map[inc]}" == "LS" ]]
        then
            data_aves[5]=$(bc <<< ${data_aves[5]}+${tail_lat_00[n]})
            data_aves[6]=$(bc <<< ${data_aves[6]}+${tail_lat_99[n]})
        fi

        n=$((n+1))
    done

    if (($num_exp != $loop))
    then
        echo ""
        echo "ERROR: Issue reading outputs. Num experiments ran doesn't match num read from output files"
        echo "Expected $loop instances of match string in one or more of the files: $match_string"
        echo "One or more of the perf experiments has failed to run or the match string is not the same"
        echo "Num exp: $loop != Num exp read: $num_exp"
        error_flag=1
        exit 125
    fi

    num_TC=$(($num_cores-$num_LS))

    for ((k = 0; k < ${#data_aves[@]}; k++))
    do
        data_aves[$k]=$(bc <<< "scale=2; ${data_aves[$k]}/$num_exp")
    done

    echo "Num experiments read: $num_exp" >> exp_log.txt

    echo "=====================================================" >> exp_log.txt

    for ((k = 0; k < ${#data_aves[@]}; k++))
    do
        echo "${data_aves[$k]}" >> exp_log.txt
    done

    if [[ "${prio_map[inc]}" == "LS" ]]
    then
        ave_latency=$(bc <<< $ave_latency+${data_aves[2]})
        ave_tail_lat[0]=$(bc <<< ${ave_tail_lat[0]}+${data_aves[5]})
        ave_tail_lat[1]=$(bc <<< ${ave_tail_lat[1]}+${data_aves[6]})
    else
        aggregate_IOPs=$(bc <<< $aggregate_IOPs+${data_aves[0]})
        aggregate_bandwidth=$(bc <<< $aggregate_bandwidth+${data_aves[1]})
    fi

    echo "=====================================================" >> exp_log.txt
    
    core=$((core+1))
    inc=$((inc+1))
    echo "" >> exp_log.txt

done

if (($num_LS > 0))
then
    ave_latency=$(bc <<< "scale=2; $ave_latency/$num_LS")
    ave_tail_lat[0]=$(bc <<< "scale=2; ${ave_tail_lat[0]}/$num_LS")
    ave_tail_lat[1]=$(bc <<< "scale=2; ${ave_tail_lat[1]}/$num_LS")
else
    ave_latency="-no LS cores-"
fi 

if (($num_TC == 0))
then
    aggregate_IOPs="-no TC cores-"
    aggregate_bandwidth="-no TC cores-"
fi

echo "=======================================================================" >> exp_log.txt
echo -e "Experiment Params: \n-w $iotype $m_arg_input\n-t $runtime \nwindow size=$windowsize \nnumber cores=$num_cores \npriority map=[${prio_map[@]}]" >> exp_log.txt
echo "=======================================================================" >> exp_log.txt

echo "=====================" >> exp_all_output.txt
echo -e "Experiment Params: \n-t $runtime \nwindow size=$windowsize \nnumber cores=$num_cores \npriority map=[${prio_map[@]}]" >> exp_all_output.txt
echo "=====================" >> exp_all_output.txt

if (($error_flag == 0))
then
    echo "no errors detected" >> exp_log.txt
    echo "[EXP_RESULTS]: $iotype$mixed_ratio_read $(bc <<< $num_cores-$num_LS) $num_LS [no_errors_detected] $aggregate_IOPs $aggregate_bandwidth $ave_latency" >> exp_all_output.txt
    echo "$iotype$mixed_ratio_read TC:$(bc <<< $num_cores-$num_LS) LS:$num_LS" >> exp_out_tab.txt
    echo ""
fi

echo "Aggregate IOPs across TC cores: $aggregate_IOPs" >> exp_log.txt
echo "Aggregate bandwidth(MiB/s) across TC cores: $aggregate_bandwidth" >> exp_log.txt
echo "Average Latency across LS cores: $ave_latency" >> exp_log.txt
echo "" >> exp_log.txt
echo "$aggregate_IOPs" >> exp_log.txt
echo "$aggregate_bandwidth" >> exp_log.txt
echo "$ave_latency" >> exp_log.txt 
echo "${ave_tail_lat[0]}, ${ave_tail_lat[1]}" >> exp_log.txt 

echo "$aggregate_IOPs" >> exp_out_tab.txt
echo "$aggregate_bandwidth" >> exp_out_tab.txt
echo "$ave_latency" >> exp_out_tab.txt 
echo "${ave_tail_lat[0]}" >> exp_out_tab.txt
echo "${ave_tail_lat[1]}" >> exp_out_tab.txt
