# urand

Windows command-line utility that generates random output

## AUTHOR

Bill Stewart - bstewart at iname dot com

## LICENSE

Urand is covered by the GNU Public License (GPL). See the file `LICENSE` for details.

## SYSTEM REQUIREMENTS

Windows Vista x64 SP2 or later.

## DOWNLOAD

https://github.com/Bill-Stewart/urand/releases/

## USAGE

**urand** _bytecount_ [**--out=**_filename_ [**--force**]] [**--text**] [**--algorithm=**_name_] [**--buffersize=**_n_] [**--seed=**_n_] [**--quiet**]

## PARAMETERS

| Parameter                               | Description
| ---------                               | -----------
| _bytecount_                             | Number of random bytes to generate
| **--out=**_filename_, **-o** _filename_ | Output file name (omlt to write to stdout)
| **--force**                             | Overwrite existing output file
| **--text**, **-t**                      | Output as text (recommended if no output file)
| **--algorithm=**_name_, **-a** _name_   | Algorithm: **OS** (default), **LCG**, or **RTL**
| **--buffersize=**_n_, **-B** _n_        | Buffer size in KB (default is 64)
| **--seed=**_n_                          | Seed for LCG or RTL algorithms (not OS)
| **--quiet**, **-q**                     | Suppress error messages
| **--help**, **-h**                      | Show usage message

You may specify a parameter's long name (e.g., **--out**) or its short equivalent (e.g., **-o**).

Parameter names (e.g., **--force** or **-t**) are case sensitive. The argument for the **--algorithm** (**-a**) parameter is not case-sensitive.

If the output file's path or name contains whitespace, enclose the filename in `"` characters.

The program does not overwrite an existing output file unless you also specify **--force**.

## REMARKS

It is recommended to use the **--text** (**-t**) parameter if you don't specify an output file; otherwise, there may be unintended side-effects when the program outputs the random bytes to standard output (stdout).

The maximum value for _bytecount_ is 53687091200 (i.e., 50GB).

If you don't specify the **--algorithm** (**-a**) parameter, the default algorithm is **OS** (i.e., use the operating system's built-in random number generator).

The numeric argument for the **--buffersize** (**-B**) parameter is in kilobytes (KB) and must be in the range 4 to 536870912 (512MB). For example, **-B 256** specifies a 256KB memory buffer. With the **--text** (**-t**) parameter, the program allocates an additional memory buffer that is approximately 33% larger than the first; e.g., **-B 256 -t** allocates both a 256KB memory buffer and an additional buffer of approximately 341KB.

The **--seed** parameter is only used if you use the LCG or RTL algorithms; the OS algorithm ignores the **--seed** parameter.

## ALGORITHMS

The program supports the following algorithms with the **--algorithm** (**-a**) parameter:

* **OS** - Uses the Windows operating system's [**BCryptGenRandom**](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom) function. As of this writing, this OS function implements an algorithm for generating a sequence of random values that complies with the NIST SP800-90 standard (specifically, the CTR_DRBG portion of that standard).

* **LCG** - Uses a Linear Congruential Generator (LCG) algorithm that simulates a sequence of random values.

* **RTL** - Uses the Free Pascal (FPC) runtime library's (RTL) random number function to simulate a sequence of random values. As of this writing, the RTL function uses a Mersenne Twister algorithm; this has a better statistical distribution than the LCG algorithm but is considerably slower.

The random output from the OS algorithm is considered to by cryptographically secure and suitable for use in cryptographic applications.

The LCG and RTL algorithms produce pseudo-random output that is not considered cryptographically secure and should not be used in cryptographic applications.

### Seed Values

The LCG and RTL algorithms support the **--seed** parameter to specify an initial "seed" value. The **--seed** parameter's value must be a whole number between 1 and 4294967295 (inclusive). With a specified seed value, the LCG and RTL algorithms will always produce the same sequence of bytes.

Using the LCG or RTL algorithm with a seed value can be useful when you need to reproduce an exact sequence of seemingly random data.

If you don't specify **--seed**, the LCG and RTL algorithms use a seed value based on the system clock.

The OS algorithm ignores the **--seed** parameter.

## TEXT OUTPUT

If you use the **--text** (**-t**) parameter, the program does the following:

1. Fills a memory buffer with randomized bytes.

2. Converts the buffer containing the randomized bytes to its base64-encoded text string equivalent to a second memory buffer using the Windows [**CryptBinaryToString**](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptbinarytostringa) function.

3. Outputs the first _bytecount_ characters of the base64-encoded text string.

The **--text** (**-t**) parameter causes the program to run more slowly as the random byte count increases. It may be useful to increase the program's buffer size (**--buffersize** or **-B** parameter) to improve performance for large output files.

## EXAMPLES

```
PS > urand 32768 --out=test.dat
```

Creates test.dat containing 32KB (32768 bytes) of random bytes.

---

```
PS > urand 65536 --o test.dat -a LCG --seed=191
```

Creates test.dat containing 64KB of pseudo-random bytes. The seed value is arbitrary, but running this command multiple times (with different output file names) will result in the same sequence of 65536 bytes.

---

```
PS > urand 127 -t
```

Outputs a string of 127 random characters to standard output.

---

```
PS > urand 536870912 -o test.dat
```

Creates a file called test.dat with 512MB of random bytes.
