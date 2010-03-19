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

	components new TimerMilliC();

	QuickP.Boot -> MainC;
	QuickP.AMSend -> AMSenderC;
	QuickP.Receive ->AMReceiverC;
	QuickP.RadioControl -> ActiveMessageC;
	QuickP.Timer -> TimerMilliC;
	QuickP.ReadX -> AccelXC;
	QuickP.ReadY -> AccelYC;
	QuickP.Leds -> LedsC;
	QuickP.Packet -> AMSenderC;
	QuickP.Mts300Sounder -> SounderC;
}
