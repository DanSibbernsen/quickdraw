#include "Message.h"

configuration QuickDrawC {
}
implementation {
	components MainC; /* Boot sequence for QuickDraw */
	components QuickP; /* Defined in QuickP.nc */

	components ActiveMessageC;
	components new AMSenderC(MESSAGE); /* Sender of packets */
	components new AMReceiverC(MESSAGE); /* Receiver of packets */

	components new AccelYC(); /* Accelerometer sensor on the motes */

	components SounderC; /* controls the sound on the motes */
	components LedsC; /* controls LEDs on the motes */

	components new TimerMilliC() as AccelT; /* Accelerometer Timer */
	components new TimerMilliC() as StartT; /* Timer to mark the start */
	components new TimerMilliC() as CountT; /* Timer to mark the countdown */
	components new TimerMilliC() as FireT; /* Timer to mark the Fire */
	components new TimerMilliC() as DrawT; /* Timer to mark the Draw Time*/
	components new TimerMilliC() as AcknowledgmentT; /* Timer used for Acknowledgments */
	components new TimerMilliC() as SystemT; /* Used for random number generation */

	components RandomC;

	QuickP.Boot -> MainC;
	QuickP.AMSend -> AMSenderC;
	QuickP.Receive ->AMReceiverC;
	QuickP.RadioControl -> ActiveMessageC;
	QuickP.AccelTimer -> AccelT;
	QuickP.StartTimer -> StartT;
	QuickP.CountDownTimer -> CountT;
	QuickP.FireTimer -> FireT;
	QuickP.DrawTimer -> DrawT;
	QuickP.ACKTimer -> AcknowledgmentT;
	QuickP.SysTimer -> SystemT;
	QuickP.ReadY -> AccelYC;
	QuickP.Leds -> LedsC;
	QuickP.Packet -> AMSenderC;
	QuickP.Mts300Sounder -> SounderC;
	QuickP.Random -> RandomC;
	QuickP.ParameterInit -> RandomC;
}
