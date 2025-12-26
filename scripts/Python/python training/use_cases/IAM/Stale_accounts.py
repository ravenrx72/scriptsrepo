#script to check all users older than X days and disables 
import datetime
from pyad import aduser

def disable_ad_user(username):
    try:
        # Find the accounts has not logged on in 90 days by sAMAccountName (username)
        user = aduser.ADUser.from_cn(username)
        today = datetime.date.today()
        print(f"Current date: {today}")
        print(f"Checking user: {username}")
        print(f"Found user: {user.get_attribute('sAMAccountName')}")
        print(f'print last login: {user.get_last_login('datetime')}')

        # Check if the account has not logged on in 2 days
        if user.get_last_login > datetime.timedelta(days=1):
            # Disable the user account
            user.disable()
            print(f"User '{username}' has been disabled.")
        
        else:
            print(f"User '{username}' is not older than 2 days, no action taken.")

    except Exception as e:
        print(f"Error disabling user '{username}': {e}")
        
    except Exception as e:
        print(f"Error disabling user '{username}': {e}")

# Example usage
if __name__ == "__main__":
    # Replace with the actual username (sAMAccountName or CN)
    username_to_disable = input('Input username to disable  ')
    disable_ad_user(username_to_disable)
