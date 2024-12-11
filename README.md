Motion Sentry: A Real-Time 3D Object Tracking System Using FPGA

The Motion Sentry is an advanced tracking system that is made up of camera-based motion detection, servo motor control, and laser sensing to allow for real-time 3D object tracking. 
The full system utilizes an FPGA to run a pipelined background subtraction algorithm to identify motion in the x-y plane. 
With this data, the FPGA relays the position to a servo motor which translates the position into motion using pulse-width modulation (PWM).
The servo adjusts the orientation of a LiDAR sensor to capture z-axis depth information about the detected object and sends that back to the FPGA through a UART interface.
The system will take the depth information and display the results via 8-bit numerical images that represent key parameters such as object distance or velocity, providing clear and concise monitoring of the object and the systems performance.
The Motion Sentry effectively uses the FPGAs ability to handle high-bandwidth, computationally intensive tasks such as video processing and real-time pixel classification to create a tracking system. By combining parallel processing, external DRAM for memory management, and integrated control of servo and LiDAR systems, the Motion Sentry demonstrates a sophisticated design optimized for digital systems and advanced motion tracking applications.
