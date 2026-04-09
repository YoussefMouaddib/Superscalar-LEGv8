// test_loop.c — for loop, array, bitwise ops
int sum_array(int *arr, int n) {
    int total;
    int i;
    total = 0;
    for (i = 0; i < n; i = i + 1) {
        total = total + arr[i];
    }
    return total;
}

int popcount(int x) {
    int count;
    count = 0;
    while (x != 0) {
        count = count + (x & 1);
        x = x >> 1;
    }
    return count;
}
