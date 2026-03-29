#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv) {
  pid_t pid;
  int devnull;

  if (argc < 2) {
    fprintf(stderr, "usage: daemonize-exec <command> [args...]\n");
    return 1;
  }

  pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid > 0) {
    return 0;
  }

  if (setsid() < 0) {
    perror("setsid");
    return 1;
  }

  signal(SIGHUP, SIG_IGN);

  pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid > 0) {
    return 0;
  }

  if (chdir("/") != 0) {
    perror("chdir");
    return 1;
  }

  devnull = open("/dev/null", O_RDONLY);
  if (devnull >= 0) {
    dup2(devnull, STDIN_FILENO);
    close(devnull);
  }

  execvp(argv[1], &argv[1]);
  perror("execvp");
  return 1;
}
