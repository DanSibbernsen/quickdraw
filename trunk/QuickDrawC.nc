#include "Message.h"

configuration QuickDrawC {
}
implementation {
	components MainC;
	components QuickP;

	components ActiveMessageC;
	components new AMSenderC(MESSAGE);
	components new AMReceiverC(MESSAGE);

	components new AccelYC();

	components SounderC;
	components LedsC;

	components new TimerMilliC() as AccelT;
	components new TimerMilliC() as StartT;
	components new TimerMilliC() as CountT;
	components new TimerMilliC() as FireT;
	components new TimerMilliC() as DrawT;
	components new TimerMilliC() as AcknowledgmentT;
	components new TimerMilliC() as SystemT;

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
