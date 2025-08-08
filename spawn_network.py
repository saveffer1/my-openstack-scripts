import openstack
import sys
from multiprocessing import Pool, cpu_count
import itertools

def create_network_task(network_number):
    """
    create network & subnet for testing
    fast creation with multi proccessing
    """
    try:
        conn = openstack.connect()
    except openstack.exceptions.ConfigException as e:
        print(f"Error connecting to OpenStack: {e}", file=sys.stderr)
        return False

    network_name = f'spawn_network-{network_number}'
    
    try:
        octet_2 = 168 + (network_number // 256)
        octet_3 = network_number % 256

        if octet_2 > 255:
            print(f"Skipping {network_name}: IP address range exceeded.", file=sys.stderr)
            return False

        print(f"Process {network_number}: Creating network {network_name}")
        network = conn.network.create_network(name=network_name)
        
        subnet_name = f'spawn_subnet-{network_name}'
        cidr_address = f'192.{octet_2}.{octet_3}.0/24'
        
        conn.network.create_subnet(
            name=subnet_name,
            network_id=network.id,
            ip_version=4,
            cidr=cidr_address
        )
        print(f"Process {network_number}: Successfully created {network_name}")
        return True

    except Exception as e:
        print(f"Process {network_number}: An error occurred: {e}", file=sys.stderr)
        return False

if __name__ == '__main__':
    num_networks = 2005
    startnum = 20
    
    network_numbers = range(startnum, startnum + num_networks)

    print(f"Creating {num_networks} networks using {cpu_count()} processes...")

    try:
        with Pool(processes=cpu_count()) as pool:
            results = pool.starmap_async(create_network_task, zip(network_numbers))
            results.get()

    except KeyboardInterrupt:
        print("\nTermination signal received. Shutting down all processes...")
        sys.exit(1)
    
    print("\nAll networks creation process complete.")
