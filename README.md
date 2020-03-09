# Wine Bottles
### Scripts to install Windows apps in mountable Wine "bottles".

Can you play Myst on a Linux computer?  Why yes, yes you can...

In fact, you can run a large number of Windows applications on a Linux box. 
One way is to run Crossover from CodeWeavers.com.  Another way is to install 
Wine.  (Of course, Crossover is just Wine with a nice GUI & helpful wizards.)

One of the nice features of Crossover is what they call "Wine Bottles", which 
are independent Wine environments that contain one or more Windows apps.  One 
nice capability of Crossover Wine Bottles is that they can be exported in 
Wine Bottle Archive files, giving your Windows apps a degree of mobility.

So what about games?  They work in Wine/Crossover, too...  What if you start 
a game on, say, your desktop/tower PC, then you need to go somewhere with your 
laptop?  What about your game?  Your game state is stuck on your other system.

That sucks.  How can we fix this situation?  

What would be nice is to have a Wine environment, complete with its apps and 
games, be portable -- in the way that Crossover bottle archives are portable. 
Or, even more so...  As though the Wine environment were implemented on a 
thumb drive and could be moved between systems by just moving the thumb drive 
around.  Literally "plug and play"...

But you don't really want to run your Wine environments on a thumb drive.  The 
performance sucks, for one thing.  Ideally, you would have a single file that 
you can copy to another Linux system and run.  Without having to unpack and 
re-install as you need to do with Crossover archives.

How could that work?  Well, with Linux you can create a disk image file, and 
mount that to get access to the files inside.  So if we were to implement our 
Wine environment inside a disk image file, we would have a portable, single 
file to move between systems.  On top of that, it would be a lot harder to 
lose track of/overwrite the huge set of files that a Wine environment typically 
contains, because "closing an application" that lives in a disk image can 
include unmounting it from the file system entirely.

However, a disk image file has its own issues...

For one, how do you mount it?  When you're done using it, how do you unmount 
it?  And the biggest question of all -- how do you create such a thing?

You need a script...  Or a set of scripts.  A script to create this kind of 
Wine Bottle, a script to automate installing the Windows application, a script 
to automate mounting and unmounting it, etc.

In fact, in an ideal world, the disk image file would itself be a script that 
can handle its own mounting.  But once mounted in the Linux file system, you 
would still need to find the launcher for the Windows app and run that to open 
the application...

So in that ideal world, the script that mounts itself as a disk image would 
automagically hand off to an internal script in the image's root directory, 
which (being application-independent), would read an adjacent app config file  
to determine where the launcher is for the Windows application.  Then it would 
run it for you.  And when you shut down the application, it would resume and 
unmount the image file.

How cool would that be?

Well, we would need one more thing to make this ideal world perfect: A script
that builds this magical script-that's-really-a-disk-image for you.  And 
inserts the where's-the-app-launcher script and builds the app-specific config 
file as well.  AND creates a desktop launcher file so that the application can 
be launched from an icon in the GUI's dock.  (We want it all...)

That's what this repository is all about.

Oh, and Myst?  I've used these scripts to build mountable Wine bottles for all 
seven Myst games (Original Myst, Riven, Exile, Revelation, End of Ages, Uru, 
and RealMyst).  All of them run by clicking an icon: They mount themselves, 
run the game inside, save game state when you shut them down, and reside on 
disk as unmounted files when you're not playing.  Files that can be copied to 
other Linux platforms, where the games can resumed.

Of course, nothing's perfect, so I'm planning to spiff up these scripts here 
& there, make them more user-friendly for "those less technically adept", and 
test them with other applications.  But I figure if they work 100% with a set 
of Windows games that span 6 or 7 versions of Windows and 25 years of history, 
it's already pretty tight.

Stay tuned...
