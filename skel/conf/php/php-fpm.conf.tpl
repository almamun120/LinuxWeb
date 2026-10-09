[global]
pid = "@RUN@/php-@PHPVER@.pid"
error_log = "@LOGS@/php-fpm-@PHPVER@.log"
daemonize = yes
[www]
@IFROOT_SEMI@user = @RUN_USER@
@IFROOT_SEMI@group = @RUN_GROUP@
@IFROOT_SEMI@listen.owner = @RUN_USER@
@IFROOT_SEMI@listen.group = @RUN_GROUP@
listen = "@SOCK@/php-@PHPVER@.sock"
listen.mode = 0660
pm = dynamic
pm.max_children = 12
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
clear_env = no
catch_workers_output = yes
