# Brownie: OS X photo management tool

*WARNING*: This project is still in an early stage. While (barely) usable, it should be regarded as a "stone soup" project open to contributions.

![brownie.png](https://raw.githubusercontent.com/simoncozens/brownie/master/brownie.png)

Brownie is a tool for locating photo files. It is designed for speed and ease of use, allowing the user to quickly filter and find photos by source, date and location.

Unlike Photos, Lightroom or other tools, Brownie does not contain any editing tools, nor does it use a central database of photos; the idea being that rather than the complexity of tracking new, changed or removed photos, Brownie should load and locate photos fast enough that no database is needed and external applications can be used for photo editing.

## Building

* You will need to install Cocoapods (`gem install cocoapods`) unless you already have it. 
* Run `pod install`
* Open `Brownie.xcworkspace` (*not* `Brownie.xcproj`!)
* Hit the big arrow!