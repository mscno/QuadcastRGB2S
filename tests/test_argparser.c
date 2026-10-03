#include "../modules/argparser.h"
#include <sys/wait.h>
#include <unistd.h>

static int failures = 0;
static int cases = 0;

static void expect_parse(int argc, const char **argv, int expected)
{
    pid_t pid = fork();
    int status;
    cases++;
    if (pid == 0) {
        int verbose = 0;
        struct colschemes *settings;
        freopen("/dev/null", "w", stderr);
        settings = parse_arg(argc, argv, &verbose);
        /* Successful inputs must leave bounded numbers and a palette terminator. */
        if (settings->upper.br < 0 || settings->upper.br > 100 ||
            settings->upper.spd < 0 || settings->upper.spd > 100 ||
            settings->upper.dly < 0 || settings->upper.dly > 100) _exit(99);
        free(settings);
        _exit(0);
    }
    if (pid < 0 || waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != expected) {
        fprintf(stderr, "Parser case %d failed\n", cases);
        failures++;
    }
}

int main(void)
{
    const char *values[] = {"", "101", "-1", "65536", "999999999999999999999999999", "abc", "1.5"};
    size_t i;
    for (i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        const char *args[] = {"test", "-s", values[i], "solid"};
        expect_parse(4, args, argerr);
    }
    {
        const char *args[] = {"test", "-b", "100", "-s", "0", "-d", "0", "solid", "ff0000"};
        expect_parse(9, args, success);
    }
    {
        const char *args[] = {"test", "cycle", "ff0000", "00ff00", "0000ff", "ffffff", "123456", "000000", "010101", "020202", "030303", "040404"};
        expect_parse(12, args, success);
    }
    {
        const char *args[] = {"test", "cycle", "ff0000", "00ff00", "0000ff", "ffffff", "123456", "000000", "010101", "020202", "030303", "040404", "050505"};
        expect_parse(13, args, argerr);
    }
    {
        const char *colors[] = {"", "#", "1000000", "ffffffff", "ffffzz"};
        for (i = 0; i < sizeof(colors) / sizeof(colors[0]); i++) {
            const char *args[] = {"test", "solid", colors[i]};
            expect_parse(3, args, argerr);
        }
    }
    {
        const char *args[] = {"test", "solid", "#ff0000"};
        expect_parse(3, args, success);
    }
    printf("%d parser cases, %d failures\n", cases, failures);
    return failures ? 1 : 0;
}
