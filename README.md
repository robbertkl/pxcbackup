# PXCBackup

PXCBackup is a database backup tool meant for [Percona XtraDB Cluster](http://www.percona.com/software/percona-xtradb-cluster) (PXC), although it could also be used on other related systems, like a [MariaDB](https://mariadb.org) [Galera](http://galeracluster.com/products/) cluster using [XtraBackup](http://www.percona.com/software/percona-xtrabackup), for example.

The `innobackupex` script provided by Percona makes it very easy to create backups, however restoring backups can become quite complicated, since backups might need to be extracted, uncompressed, decrypted, before restoring they need to be prepared, incremental backups need to be applied on top of full backups, indexes might need to be rebuilt for compact backups, etc. Usually, backups need to be restored in stressful emergency situations, where all of these steps can slow you down quite a bit.

PXCBackup does all of this for you! As a bonus, PXCBackup provides syncing backups to [Amazon S3](http://aws.amazon.com/s3/) and even restoring straight from S3.

Since PXCBackup is meant for Galera clusters, it does a few additional things:

* Run `innobackupex` with `--galera-info` and reconstructing `grastate.dat` when restoring a backup. This preserves the local node state, allowing new nodes to be added from a backup with just an IST!

* Turning on `wsrep_desync` before a backup, and turning it off again after `wsrep_local_recv_queue` is empty. The reason for this is twofold:
  * It prevents flow control from kicking in when the backup node takes a performance hit because of the increased disk load (this is similar to what happens on a donor node, during an SST).
  * Secondly, it makes `clustercheck` report this node as unavailable, which can be very useful to let your loadbalancer(s) skip this node during the backup. This behavior can be turned off by setting `available_when_donor` to `1` in `clustercheck`.

PXCBackup is basically a server command line tool, which means the following constraints were used:

* Support ruby >= 1.8.7. Yes, 1.8.7 is EOL, but many cloud provider OS images still contain 1.8.7.
* Have no external gem dependencies. This tool should be completely stand-alone, and only require certain command line tools.
* Instead, execute command line tools. For example, it uses the `mysql` and `s3cmd` tools instead of modules / gems.

## Installation

Simply install the gem:

```shell
$ gem install pxcbackup
```

Of course, you need to have PXC (or similar) running, which provides most of the tools (`innobackupex`, `xtrabackup`, `xbstream`, `xbcrypt`).

To sync to Amazon S3, make sure you have [S3cmd](http://s3tools.org/s3cmd) installed and configured (`s3cmd --configure`, which creates a file `~/.s3cfg`).

## Usage

Just check the built in command line help:

```shell
$ pxcbackup help
```

Aside from command line flags, you can specify additional options in `~/.pxcbackup`, or another
config given by `-c`. Some commonly used settings are:

```yaml
backup_dir: /path/to/local/backups/
remote: s3://my-aws-bucket/
mysql_username: root
mysql_password:
compact: false
compress: true
encrypt: AES256
encrypt_key: <secret-key>
retention: 100
desync_wait: 30
threads: 4
memory: 1G
```

## Wishlist

* More complex rotation schemes
* Separate rotation scheme for remote
* Better error handling for shell commands
* Code documentation (RDoc?)
* Tests (RSpec?)
* Different remote providers

## Authors

* Robbert Klarenbeek, <robbertkl@renbeek.nl>

## License

DeployHook is published under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
