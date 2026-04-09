// test_hello.c — basic function, arithmetic, return value
int add(int a, int b) {
    return a + b;
}

int main() {
    int x;
    int y;
    x = 10;
    y = 32;
    return add(x, y);   // should return 42
}
