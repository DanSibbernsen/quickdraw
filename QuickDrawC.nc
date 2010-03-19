#include "Message.h"

configuration QuickDrawC {
}
implementation {
	components MainC;
	components QuickP;

	components ActiveMessageC;
	components new AMSenderC(MESSAGE);
	components new AMReceiverC(MESSAGE);

	components new AccelXC();
	components new AccelYC();

	components SounderC;
	components LedsC;

	components new TimerMilliC() as AccelT;
	components new TimerMilliC() as StartT;
	components new TimerMilliC() as CountT;

	QuickP.Boot -> MainC;
	QuickP.AMSend -> AMSenderC;
	QuickP.Receive ->AMReceiverC;
	QuickP.RadioControl -> ActiveMessageC;
	QuickP.AccelTimer -> AccelT;
	QuickP.StartTimer -> StartT;
	QuickP.CountDownTimer -> CountT;
	QuickP.ReadX -> AccelXC;
	QuickP.ReadY -> AccelYC;
	QuickP.Leds -> LedsC;
	QuickP.Packet -> AMSenderC;
	QuickP.Mts300Sounder -> SounderC;
}
