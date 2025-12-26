
#Here’s a Python script to disable a user in Active Directory using the pyad library, which interfaces with Active Directory via COM under Windows. 

#This script requires:
#You run it on a Windows machine that is domain-joined.
#You have sufficient permissions to disable users.
#pyad is installed (pip install pyad).
#also install   (pip install pywin32)
#Python must be running as a user with AD permissions (or you provide credentials).


from pyad import aduser

def disable_ad_user(username):
    try:
        # Find the user by sAMAccountName (username)
        user = aduser.ADUser.from_cn(username)
        print(f"Found user: {user.get_attribute('sAMAccountName')}, LastLogon: {user.get_attribute('LastLogon')}")

        # Disable the user account
        user.disable()
        print(f"User '{username}' has been disabled.")
        
    except Exception as e:
        print(f"Error disabling user '{username}': {e}")

# Example usage
if __name__ == "__main__":
    # Replace with the actual username (sAMAccountName or CN)
    username_to_disable = input('Input username to disable  ')
    disable_ad_user(username_to_disable)
