
# swiftysign







[![Build Status](https://travis-ci.org/michaelspecht/swiftysign.svg?branch=master)](https://travis-ci.org/michaelspecht/swiftysign)



Re-sign IPAs from command line or an easy-to-use UI. This can be used to create separate apps from the same initial app for testing (for instance, creating a beta app with a different bundle identifier from the production app, but from the same artifact).

> _The command line utility also supports updating any number of Info.plist values. For instance, you can change an environment variable that the app can use to direct the user to a test URL instead of hitting the production URL._



To get started just:

- Specify the path to the .xcarchive file

- Specify the path to the mobile provisioning file

- Select a signing certificate

- Optionally, specify a new bundle ID or display name

- Click ****Re-sign App****



Voila! You should now have the modified IPA available in the same directory as the original xcarchive.



Command line use is also supported

> ./**swiftysign**
>  **-archive** path/to/archive.xcarchive
> **-provpath** path/to/provision.mobileprovision
> **-cert** certificatename
> [**-newbundleid** new.bundle.identifier]
> [**-newappname** NewAppName]
> [**-entitlements** path/to/entitlements.plist]
> [**-newplistvalue** key newValue]



## Credit



Originally based off of https://github.com/qiaoxueshi/iReSign



## License

Swiftysign is available under the MIT license.



THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
