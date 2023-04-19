sudo ./scripts/rpc.py nvmf_create_transport -t TCP
sudo ./scripts/rpc.py nvmf_create_subsystem -s SPDK00000000000001 -a -m 32 nqn.2016-06.io.spdk:cnode1
sudo ./scripts/rpc.py bdev_nvme_attach_controller -b NVMe1 -t PCIe -a 0000:c1:00.0
sudo ./scripts/rpc.py nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 NVMe1n1
sudo ./scripts/rpc.py nvmf_subsystem_add_listener -t tcp -f Ipv4 -a 10.10.1.6 -s 4420 nqn.2016-06.io.spdk:cnode1
