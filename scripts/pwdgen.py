import random
import string

def generate_password(length=20):
    if length < 4:  # Ensure there's enough length for at least one of each character type
        raise ValueError("Password length must be at least 4 characters.")

    # Define character sets
    letters = string.ascii_letters
    digits = string.digits
    special_chars = '!@#$%^&*()_+-='

    # Ensure at least one character from each category
    password = [
        random.choice(letters),
        random.choice(digits),
        random.choice(special_chars)
    ]

    # Fill the rest of the password length with random choices from all categories
    all_chars = letters + digits + special_chars
    password += random.choices(all_chars, k=length - 3)

    # Shuffle the password list to ensure randomness
    random.shuffle(password)

    # Join the list into a string and return
    return ''.join(password)

# Generate and print the password
print(generate_password(20))