# Simple FizzBuzz implementation for testing purposes
# Prints numbers 1-100, replacing multiples of 3 with "Fizz", 
# multiples of 5 with "Buzz", and multiples of both with "FizzBuzz"

def fizzbuzz(n):
    """
    Classic FizzBuzz implementation
    Returns 'Fizz' for multiples of 3, 'Buzz' for multiples of 5,
    'FizzBuzz' for multiples of both, otherwise the number itself
    """
    if n % 15 == 0:
        return "FizzBuzz"
    elif n % 3 == 0:
        return "Fizz"
    elif n % 5 == 0:
        return "Buzz"
    else:
        return str(n)

def print_fizzbuzz(start=1, end=100):
    """Print FizzBuzz sequence from start to end"""
    for i in range(start, end + 1):
        print(fizzbuzz(i))

if __name__ == "__main__":
    print("Starting FizzBuzz from 1 to 100:")
    print_fizzbuzz()
    print("FizzBuzz complete!")