// Tiny launcher for discord_cache_to_md.py, built into "Sentient Discord Reader.app" by install.sh.
//
// Discord's data folder is protected by macOS, so the nightly job needs Full Disk Access. Granting
// that to python itself would hand it to every Python script; instead this signed app holds the
// grant. macOS attributes a child process's file access to the app that started it, so python runs
// as a CHILD here. exec() would turn this process into python and lose the grant.
#include <limits.h>
#include <pwd.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <mach-o/dyld.h>

extern char **environ;

int main(int argc, char **argv) {
    const char *home = getenv("HOME");
    if (!home || !*home) {
        struct passwd *pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : "";
    }
    char script[PATH_MAX];
    snprintf(script, sizeof script, "%s/.sentient/discord_cache_to_md.py", home);

    // Tell the script which app holds the grant, so its permission error names the right thing.
    char exe[PATH_MAX];
    uint32_t n = sizeof exe;
    if (_NSGetExecutablePath(exe, &n) == 0) {
        char *app = strstr(exe, ".app/Contents/MacOS/");
        if (app) app[4] = '\0';
        setenv("DISCORD_READER_APP", exe, 1);
    }

    char **args = calloc((size_t)argc + 2, sizeof *args);
    args[0] = "/usr/bin/python3";
    args[1] = script;
    for (int i = 1; i < argc; i++) args[i + 1] = argv[i];

    pid_t pid;
    int err = posix_spawn(&pid, args[0], NULL, NULL, args, environ);
    if (err) {
        fprintf(stderr, "could not start %s: %s\n", args[0], strerror(err));
        return 1;
    }
    int status;
    if (waitpid(pid, &status, 0) < 0) return 1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
