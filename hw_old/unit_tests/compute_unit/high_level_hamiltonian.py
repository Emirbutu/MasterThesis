"""
Hamiltonian Energy Calculation Utilities
Ising model: H = sigma^T * J * sigma
where sigma is a binary vector (0 or 1) mapped to spins (-1 or +1)
"""

import numpy as np


def calculate_hamiltonian(sigma, J):
    """
    Calculate Hamiltonian energy: H = sigma^T * J * sigma
    
    Args:
        sigma: Binary vector (numpy array) where 0 maps to spin -1, 1 maps to spin +1
        J: Coupling matrix (numpy array, square matrix)
    
    Returns:
        Scalar energy value
    
    Example:
        >>> sigma = np.array([1, 1, 0, 1])
        >>> J = np.ones((4, 4)) * 3
        >>> energy = calculate_hamiltonian(sigma, J)
    """
    # Convert binary (0/1) to spins (-1/+1)
    spins = 2 * sigma - 1
    
    # Calculate H = spins^T * J * spins
    energy = spins.T @ J @ spins
    
    return int(energy)


def calculate_energy_difference(sigma_old, sigma_new, J):
    """
    Calculate energy difference: Delta_H = H_new - H_old
    
    Args:
        sigma_old: Old binary vector (numpy array)
        sigma_new: New binary vector (numpy array)
        J: Coupling matrix (numpy array, square matrix)
    
    Returns:
        Energy difference (scalar)
    
    Example:
        >>> sigma_old = np.ones(256)
        >>> sigma_new = np.zeros(256)
        >>> J = np.ones((256, 256)) * 3
        >>> delta = calculate_energy_difference(sigma_old, sigma_new, J)
    """
    energy_old = calculate_hamiltonian(sigma_old, J)
    energy_new = calculate_hamiltonian(sigma_new, J)
    
    return energy_new - energy_old


def generate_constant_j_matrix(size, const_val):
    """
    Generate a constant J matrix
    
    Args:
        size: Matrix dimension (N x N)
        const_val: Constant value for all elements
    
    Returns:
        numpy array of shape (size, size)
    """
    return np.ones((size, size)) * const_val


def generate_random_j_matrix(size, max_val):
    """
    Generate a random J matrix with integer values
    
    Args:
        size: Matrix dimension (N x N)
        max_val: Maximum value (inclusive)
    
    Returns:
        numpy array of shape (size, size) with random integers [0, max_val]
    """
    return np.random.randint(0, max_val + 1, size=(size, size))


def verify_global_flip_symmetry(J):
    """
    Verify that flipping all spins leaves energy unchanged
    This should always be true for Ising models without bias
    
    Args:
        J: Coupling matrix
    
    Returns:
        True if symmetry holds, False otherwise
    """
    size = J.shape[0]
    sigma_all_ones = np.ones(size)
    sigma_all_zeros = np.zeros(size)
    
    energy_ones = calculate_hamiltonian(sigma_all_ones, J)
    energy_zeros = calculate_hamiltonian(sigma_all_zeros, J)
    
    delta = energy_ones - energy_zeros
    
    print(f"Energy(all +1): {energy_ones}")
    print(f"Energy(all -1): {energy_zeros}")
    print(f"Delta: {delta}")
    
    return delta == 0


def generate_sigma_f(sigma_previous, sigma_new):
    """
    Generate sigma_f and sigma_f_inv from sigma_previous and sigma_new
    sigma_f = XOR to find flipped bits
    sigma_f_inv = NOT sigma_f (non-flipped bits)
    
    Args:
        sigma_previous: Previous binary vector (numpy array)
        sigma_new: New binary vector (numpy array)
    
    Returns:
        Tuple of (sigma_f, sigma_f_inv)
    """
    sigma_f = np.logical_xor(sigma_previous, sigma_new).astype(int)
    sigma_f_inv = np.logical_not(sigma_f).astype(int)
    return sigma_f, sigma_f_inv


def generate_sigma_c(sigma_f, sigma_new, vector_size):
    """
    Generate sigma_c from sigma_f and sigma_new
    sigma_c encoding: 0 = zero, +1 = positive element, -1 = negative element
    
    Args:
        sigma_f: Flipped bits mask (numpy array)
        sigma_new: New sigma state (numpy array)
        vector_size: Active vector size
    
    Returns:
        numpy array with encoding: 0, +1, or -1
    """
    sigma_c = np.zeros(sigma_f.shape[0], dtype=int)
    
    for i in range(vector_size):
        if sigma_f[i]:
            sigma_c[i] = 1 if sigma_new[i] else -1
        else:
            sigma_c[i] = 0
    
    return sigma_c


def generate_sigma_r(sigma_f_inv, sigma_new, vector_size):
    """
    Generate sigma_r from sigma_f_inv and sigma_new
    sigma_r encoding: 0 = zero, +1 = positive element, -1 = negative element
    
    Args:
        sigma_f_inv: Non-flipped bits mask (numpy array)
        sigma_new: New sigma state (numpy array)
        vector_size: Active vector size
    
    Returns:
        numpy array with encoding: 0, +1, or -1
    """
    sigma_r = np.zeros(sigma_f_inv.shape[0], dtype=int)
    
    for i in range(vector_size):
        if sigma_f_inv[i]:
            sigma_r[i] = 1 if sigma_new[i] else -1
        else:
            sigma_r[i] = 0
    
    return sigma_r


def calculate_expected_output(sigma_r, sigma_c, J, col_per_cc, vector_size):
    """
    Calculate expected output from compute_unit (software model)
    Models hardware computation: sigma_r * J * sigma_c
    
    Args:
        sigma_r: Row encoding (numpy array): 0, +1, or -1
        sigma_c: Column encoding (numpy array): 0, +1, or -1
        J: Coupling matrix (numpy array)
        col_per_cc: Number of columns per cycle
        vector_size: Vector size (rows)
    
    Returns:
        Total energy sum
    """
    total_sum = 0
    
    # Process each column
    for col in range(col_per_cc):
        column_sum = 0
        
        # Compute dot product for this column
        for row in range(vector_size):
            column_sum += sigma_r[row] * J[col, row]
        
        # Apply sigma_c sign selection
        total_sum += sigma_c[col] * column_sum
    
    return int(total_sum)


def energy_from_columns_full(sigma_bits, J, vector_size):
    """
    Compute full energy using column-wise accumulation
    sigma_bits encodes spins: +1 or -1
    
    Args:
        sigma_bits: Spin vector (+1 or -1)
        J: Coupling matrix (numpy array)
        vector_size: Size of active region
    
    Returns:
        Total energy
    """
    total_energy = 0
    
    # Process each column, all rows
    for col in range(vector_size):
        column_contribution = 0
        sigma_c_val = sigma_bits[col]
        
        for row in range(vector_size):
            sigma_r_val = sigma_bits[row]
            column_contribution += sigma_r_val * J[col, row]
        
        total_energy += sigma_c_val * column_contribution
    
    return int(total_energy)


def verify_iterative_vs_hamiltonian(sigma_old, sigma_new, J, vector_size):
    """
    Verify iterative column processing matches full Hamiltonian energy difference
    
    Args:
        sigma_old: Old binary vector (numpy array)
        sigma_new: New binary vector (numpy array)
        J: Coupling matrix (numpy array)
        vector_size: Active vector size
    
    Returns:
        Tuple of (match, iterative_result, hamiltonian_result)
    """
    # Convert to spin encodings (+1 or -1)
    spins_old = 2 * sigma_old - 1
    spins_new = 2 * sigma_new - 1
    
    # Column-wise energies
    energy_new_cols = energy_from_columns_full(spins_new, J, vector_size)
    energy_old_cols = energy_from_columns_full(spins_old, J, vector_size)
    iterative_result = energy_new_cols - energy_old_cols
    
    # Full Hamiltonian energy difference
    hamiltonian_result = calculate_energy_difference(sigma_old, sigma_new, J)
    
    match = (iterative_result == hamiltonian_result)
    
    return match, iterative_result, hamiltonian_result


if __name__ == "__main__":
    # Test 1: Constant J matrix with all spins +1
    print("=== TEST 1: Constant J, all spins +1 ===")
    N = 256
    const_val = 3
    J = generate_constant_j_matrix(N, const_val)
    sigma = np.ones(N)
    
    energy = calculate_hamiltonian(sigma, J)
    expected = N * N * const_val
    
    print(f"Vector size: {N}")
    print(f"J constant value: {const_val}")
    print(f"Expected energy (N*N*C): {expected}")
    print(f"Calculated energy: {energy}")
    print(f"Match: {energy == expected}\n")
    
    # Test 2: Global flip should give delta = 0
    print("=== TEST 2: Global flip (delta should be 0) ===")
    sigma_old = np.ones(N)
    sigma_new = np.zeros(N)
    
    delta = calculate_energy_difference(sigma_old, sigma_new, J)
    print(f"Delta (expected 0): {delta}")
    print(f"Match: {delta == 0}\n")
    
    # Test 3: Single spin flip
    print("=== TEST 3: Single spin flip ===")
    sigma_old = np.ones(N)
    sigma_new = np.ones(N)
    sigma_new[0] = 0  # Flip first spin
    
    delta = calculate_energy_difference(sigma_old, sigma_new, J)
    
    print(f"Flipped spin[0] from +1 to -1")
    print(f"Calculated delta: {delta}\n")
    
    # Test 4: Verify global flip symmetry
    print("=== TEST 4: Global flip symmetry check ===")
    is_symmetric = verify_global_flip_symmetry(J)
    print(f"Symmetry holds: {is_symmetric}\n")
    
    # Test 5: Verify iterative vs Hamiltonian (column-wise computation)
    print("=== TEST 5: Iterative vs Hamiltonian ===")
    sigma_old = np.ones(N)
    sigma_new = np.ones(N)
    sigma_new[0] = 0  # Flip first spin
    
    match, iter_result, ham_result = verify_iterative_vs_hamiltonian(
        sigma_old, sigma_new, J, N
    )
    
    print(f"Iterative result: {iter_result}")
    print(f"Hamiltonian result: {ham_result}")
    print(f"Match: {match}\n")
    
    # Test 6: Verify sigma generation functions
    print("=== TEST 6: Sigma generation functions ===")
    sigma_prev = np.array([1, 1, 0, 1, 0, 0, 1, 0])
    sigma_new_test = np.array([1, 0, 1, 1, 0, 1, 0, 0])
    
    sigma_f, sigma_f_inv = generate_sigma_f(sigma_prev, sigma_new_test)
    sigma_c = generate_sigma_c(sigma_f, sigma_new_test, 8)
    sigma_r = generate_sigma_r(sigma_f_inv, sigma_new_test, 8)
    
    print(f"sigma_prev:  {sigma_prev}")
    print(f"sigma_new:   {sigma_new_test}")
    print(f"sigma_f:     {sigma_f} (flipped bits)")
    print(f"sigma_f_inv: {sigma_f_inv} (non-flipped bits)")
    print(f"sigma_c:     {sigma_c} (column encoding)")
    print(f"sigma_r:     {sigma_r} (row encoding)\n")
    
    # Test 7: Calculate expected output (hardware model)
    print("=== TEST 7: Hardware model output ===")
    J_small = generate_constant_j_matrix(8, 2)
    
    # Test with constant J and simple flip pattern
    sigma_old_test = np.ones(8)
    sigma_new_test_hw = np.ones(8)
    sigma_new_test_hw[1] = 0  # Flip bit 1
    sigma_new_test_hw[3] = 0  # Flip bit 3
    
    # Generate sigma_f, sigma_r, sigma_c
    sigma_f_test, sigma_f_inv_test = generate_sigma_f(sigma_old_test, sigma_new_test_hw)
    sigma_r_hw = generate_sigma_r(sigma_f_inv_test, sigma_new_test_hw, 8)
    sigma_c_hw = generate_sigma_c(sigma_f_test, sigma_new_test_hw, 8)
    
    # Convert sigma_c from 0/+1/-1 to 0/1 for hardware model
    sigma_c_1bit = np.where(sigma_c_hw == 1, 1, 0)
    
    print(f"sigma_old:  {sigma_old_test}")
    print(f"sigma_new:  {sigma_new_test_hw}")
    print(f"sigma_r:    {sigma_r_hw}")
    print(f"sigma_c:    {sigma_c_hw}")
    print(f"sigma_c_1bit: {sigma_c_1bit}")
    
    # Calculate using hardware model
    hw_output = calculate_expected_output(sigma_r_hw, sigma_c_1bit, J_small, 8, 8)
    
    # Calculate actual energy difference for comparison
    delta_actual = calculate_energy_difference(sigma_old_test, sigma_new_test_hw, J_small)
    
    print(f"Hardware model output: {hw_output}")
    print(f"Actual energy delta:   {delta_actual}")
    print(f"Note: Hardware output processes only flipped columns\n")
