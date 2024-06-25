# Nextflow Support

Some general purpose things to help support Nextflow pipelines.

Here we have some Groovy scripts to be run as part of a task and some
Nextflow functions for use in a pipeline.

## Nextflow Functions

### `functions.nf`

`functions.nf` contains some functions that may be of use in a finished
pipeline.

#### `javaMemMB`

This function subtracks 64MB from the task's allocated memory to give a
number that can be given to the JVM's `-Xms` and `-Xmx` command line
parameters for setting the heap size. It is estimated that the 64MB is needed
for the JVM itself and the rest of the memory given to the task can be used
by the heap.

The function insists on a minimum of 16MB left for the heap, so a task using
this function needs a minimum of 96MB given to it. An exception is thrown
if there is too little memory given to the task.

#### `sizeOf`

`sizeOf` is an attempt to get the number of things in a collection. Nextflow
will often return a single item as a thing or a collection or two or more items
(file globbing is the main culprit). Often we need to know how many things we
have and can't simple call `size()` on the item, as it may or may not be a
collection. This function returns the size of the collection or map if it is
one of those, otherwise it returns 1 unless the thing is _null_, in which case
it returns 0.

See https://github.com/nextflow-io/nextflow/issues/2425

#### `makeCollection`

`makeCollection` handles the same problem as `sizeOf`, but ensures that the
thing returned is indeed a collection. So anything that's already a collection
is returned as is, whereas single items are wrapped in a list of length 1.

### `debugging.nf`

`debugging.nf` contains a function that is of use while trying to develop
a pipeline. `logException` logs any _Throwable_ to the log at error level,
but it handles Java's _InvocationTargetException_ by extracting the target
exception and logging that. It is very common for the exceptions coming out of
the Nextflow system to display as the wrapping _InvocationTargetException_
only, which hides the real problem.

## Supporting Scripts

The Groovy scripts in this package handle some shortcomings in the system that
isn't Nextflow's fault. They need to be run in your tasks if they are used.

Note that the Maven `pom.xml` and the structure under `src` provide unit
tests for the Groovy scripts. One doesn't need Maven to use the scripts.

### `outOfMemoryCheck.groovy`

This script is designed to handle problems when a Java or Groovy task fails due
to not having enough memory. Unless explicitly handled by the developer of the
code, a Java _OutOfMemoryError_ will dump a stack trace but the task will exit
with the code 1. This doesn't help Nextflow's retry mechanism because that
exit code could mean anything. This Groovy script scans `.command.log` for
the fully qualified exception string, i.e. `java.lang.OutOfMemoryError`.
If it is found, the script exits with error code 104 (by default) rather than
the error code from the task itself.

It should be added to scripts immediately after the Java code:

```BASH
java ...

groovy <path>/outOfMemoryCheck.groovy $?
```

Thus the exit code passed in is given to the Groovy script to return itself
unless an out of memory message is found, in which case exit code 104 is returned.

One can provide a different code to use if memory runs out with a second argument
to the command line:

```
groovy <path>/outOfMemoryCheck.groovy $? 137
```

This example will return code 137 if an out of memory message is found.

### `removeInput.groovy`

`removeInput.groovy` is a means of controlling the amount of intermediate
files filling the disk while Nextflow runs. The Nextflow system provides a
[`cleanup`](https://www.nextflow.io/docs/latest/config.html#miscellaneous)
option that removes the work directory automatically if the pipeline succeeds,
but when there is a large amount of disk used before that point it's not a
solution.

This script will navigate any symbolic link to its target file and remove it
before removing the link itself (symlinks are the most common way things are
staged into Nextflow tasks). One needs to supply the file or files to be removed
to the script. For example, with an input "file1":

```
groovy <path>/removeInput.groovy true $? "!{file1}"
```

The first two arguments control the script. The first is a simple boolean
parameter to say whether to do this at all. Removing the inputs will probably
prevent the pipeline being resumed so this system should only be used when
necessary. To that end, it is advised to control it with a boolean parameter
that is by default false:

```
params.EAGER_CLEAN = false
```

Then the example is better written:

```
groovy <path>/removeInput.groovy !{params.EAGER_CLEAN} $? "!{file1}"
```

Thus if problems are found with disk usage, one can run the pipeline with
`EAGER_CLEAN` set to true and this keen input removal will work.

The second argument is the exit code of the process that is actually doing
the work. It is provided because removing the input should only happen if the
task has succeeded. Anything other than zero will leave the input where it
is.

These first two parameters are provided like this because it's simpler to
write the call as above than to wrap the call in some BASH conditional blocks.
Just call the script anyway and let it decide whether to remove the input
or not.

One needs to be very careful with this script that the output from the preceding
task is not used by more than one following task. You cannot use this if the
input is used by multiple instances of a process.
