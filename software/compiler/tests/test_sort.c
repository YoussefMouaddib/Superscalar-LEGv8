// test_sort.c — bubble sort, the demo we want running on the FPGA
// This is the kind of program the compiler needs to handle correctly.

int swap(int *a, int *b) {
    int tmp;
    tmp = *a;
    *a = *b;
    *b = tmp;
    return 0;
}

int bubble_sort(int *arr, int n) {
    int i;
    int j;
    for (i = 0; i < n - 1; i = i + 1) {
        for (j = 0; j < n - i - 1; j = j + 1) {
            if (arr[j] > arr[j + 1]) {
                swap(arr + j, arr + j + 1);
            }
        }
    }
    return 0;
}

int sum(int *arr, int n) {
    int total;
    int i;
    total = 0;
    for (i = 0; i < n; i = i + 1) {
        total = total + arr[i];
    }
    return total;
}

int main() {
    return 42;
}
